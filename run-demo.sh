set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$ROOT/manifests"

PROVISION="${PROVISION:-false}"
IMAGE_FORMAT="${IMAGE_FORMAT:-live-iso}"

BOLD=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

section() { printf '\n%s%s== %s ==%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
info()    { printf '%s -> %s%s\n' "$GREEN" "$1" "$RESET"; }
warn()    { printf '%s !! %s%s\n' "$YELLOW" "$1" "$RESET"; }

trap 'echo; warn "Failed at line $LINENO. Fix the cause and re-run ./run-demo.sh — steps are idempotent."; exit 1' ERR

enable_kubevirt_hotplug() {
  section "KubeVirt: enable DeclarativeHotplugVolumes"
  # KubeVirtBMC hotplugs the cdrom volume onto the VM when Ironic issues a
  # Redfish "insert virtual media" call — needs this feature gate on.
  kubectl patch kubevirt kubevirt -n kubevirt --type merge \
    -p '{"spec":{"configuration":{"developerConfiguration":{"featureGates":["DeclarativeHotplugVolumes"]}}}}'
  kubectl -n kubevirt wait --for=condition=Available kubevirt/kubevirt --timeout=180s
}

configure_storage_profile() {
  section "CDI: configuring StorageProfile"
  # kind's default StorageClass (local-path-provisioner) doesn't advertise
  # CSI capabilities, so CDI can't auto-populate the StorageProfile's
  # claimPropertySets. Without this, any DataVolume CDI creates (e.g. the
  # one KubeVirtBMC creates for cdrom virtual-media hotplug) fails with:
  #   "no accessMode specified in StorageProfile <name>"
  local sc="${STORAGE_CLASS:-}"
  if [[ -z "$sc" ]]; then
    sc="$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')"
  fi
  if [[ -z "$sc" ]]; then
    warn "no default StorageClass found and STORAGE_CLASS not set — skipping. If DataVolumes fail with 'no accessMode specified', set STORAGE_CLASS and re-run."
    return
  fi
  kubectl patch storageprofile "$sc" --type=merge \
    -p '{"spec":{"claimPropertySets":[{"accessModes":["ReadWriteOnce"],"volumeMode":"Filesystem"}]}}'
  info "patched StorageProfile/$sc"
}

install_kubevirtbmc() {
  section "KubeVirtBMC"
  kubectl apply -f https://github.com/kubevirtbmc/kubevirtbmc/releases/latest/download/kubevirtbmc-install.yaml
  kubectl -n kubevirtbmc-system wait --for=condition=Ready pods \
    -l app.kubernetes.io/name=kubevirtbmc --timeout=120s
}

deploy_vm() {
  section "Demo VM + VirtualMachineBMC"
  kubectl apply -f "$MANIFESTS/00-vm-pvc.yaml"
  kubectl apply -f "$MANIFESTS/01-vm.yaml"
  kubectl apply -f "$MANIFESTS/02-vm-bmc.yaml"
  kubectl -n default wait --for=condition=Ready virtualmachinebmcs/demo-bmc --timeout=120s
  kubectl get virtualmachinebmcs -n default
  kubectl get svc -n default -l kubevirt.io/virtualmachinebmc-name=demo-bmc
}

wait_for_bmh_state() {
  local name=$1 want=$2 timeout=${3:-1800}
  local start now state error
  start=$(date +%s)
  info "waiting for bmh/$name to reach state '$want' (timeout ${timeout}s)"
  while true; do
    state=$(kubectl -n default get bmh "$name" -o jsonpath='{.status.provisioning.state}' 2>/dev/null || true)
    error=$(kubectl -n default get bmh "$name" -o jsonpath='{.status.errorMessage}' 2>/dev/null || true)
    printf '    [%4ds] state=%s%s\n' "$(( $(date +%s) - start ))" "${state:-<none>}" "${error:+  error=$error}"
    [[ "$state" == "$want" ]] && { info "reached '$want'"; return 0; }
    now=$(date +%s)
    if (( now - start > timeout )); then
      echo "ERROR: timed out waiting for bmh/$name to reach '$want' (last state: $state)" >&2
      return 1
    fi
    sleep 10
  done
}

create_bmh() {
  section "BareMetalHost"
  kubectl apply -f "$MANIFESTS/06-bmh.yaml"
  kubectl get bmh -n default
  # registering -> inspecting -> preparing -> available; slow under
  # software emulation since it boots the IPA ramdisk via virtual media.
  wait_for_bmh_state metal3-demo-vm available 1800
  kubectl get bmh metal3-demo-vm -n default -o jsonpath='{.status.hardware}' | (command -v jq >/dev/null && jq . || cat)
  echo
}

provision_host() {
  section "Provisioning (image install)"
  if [[ "$IMAGE_FORMAT" == "qcow2" ]]; then
    patch_file="$MANIFESTS/08-bmh-image-qcow2.yaml"
  else
    patch_file="$MANIFESTS/07-bmh-image-live-iso.yaml"
  fi

  if [[ -n "${IMAGE_URL:-}" ]]; then
    tmp="$(mktemp)"
    if [[ "$IMAGE_FORMAT" == "qcow2" ]]; then
      printf 'spec:\n  image:\n    url: "%s"\n    checksum: "%s"\n    checksumType: auto\n    format: qcow2\n' \
        "$IMAGE_URL" "${IMAGE_CHECKSUM:?IMAGE_CHECKSUM required when IMAGE_FORMAT=qcow2 and IMAGE_URL is overridden}" > "$tmp"
    else
      printf 'spec:\n  image:\n    url: "%s"\n    format: live-iso\n' "$IMAGE_URL" > "$tmp"
    fi
    patch_file="$tmp"
  fi

  kubectl patch bmh metal3-demo-vm -n default --type=merge --patch-file="$patch_file"
  wait_for_bmh_state metal3-demo-vm provisioned 1800
}

summary() {
  section "Done"
  kubectl get bmh -n default
  kubectl get vm -n default
  echo
  info "Explore further with:"
  echo "    kubectl get bmh metal3-demo-vm -n default -o yaml"
  echo "    kubectl get vm metal3-demo-vm -n default -o yaml"
  echo "    virtctl console metal3-demo-vm -n default   # watch it boot"
  echo
  if [[ "$PROVISION" != "true" ]]; then
    info "Host is 'available' but not provisioned. To provision live:"
    echo "    PROVISION=true $0"
    echo "  or just run:  provision_host  (source this script, or copy the kubectl patch from manifests/07-bmh-image-live-iso.yaml)"
  fi
}

main() {
  enable_kubevirt_hotplug
  configure_storage_profile
  install_kubevirtbmc
  deploy_vm
  create_bmh
  if [[ "$PROVISION" == "true" ]]; then
    provision_host
  fi
  summary
}

main "$@"
