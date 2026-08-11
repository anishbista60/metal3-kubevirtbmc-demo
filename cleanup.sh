set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$ROOT/manifests"
VENDOR="$ROOT/vendor"

BOLD=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
section() { printf '\n%s%s== %s ==%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
info()    { printf '%s -> %s%s\n' "$GREEN" "$1" "$RESET"; }

KEEP_REPOS=false
[[ "${1:-}" == "--keep-repos" ]] && KEEP_REPOS=true

section "BareMetalHost"
kubectl delete -f "$MANIFESTS/06-bmh.yaml" --ignore-not-found

section "Demo VM + VirtualMachineBMC"
kubectl delete -f "$MANIFESTS/02-vm-bmc.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/01-vm.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/00-vm-pvc.yaml" --ignore-not-found

section "Bare Metal Operator"
if [[ -d "$VENDOR/baremetal-operator/.git" ]]; then
  ( cd "$VENDOR/baremetal-operator" \
    && kustomize build config/overlays/kubevirtbmc-demo | kubectl delete -f - --ignore-not-found )
else
  info "vendor/baremetal-operator not present, skipping"
fi

section "Ironic"
kubectl delete -f "$MANIFESTS/05-ironic.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/04-ironic-credentials.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/03-ironic-certs.yaml" --ignore-not-found
kubectl delete ns baremetal-operator-system --ignore-not-found

section "Ironic Standalone Operator"
if [[ -d "$VENDOR/ironic-standalone-operator/.git" ]]; then
  ( cd "$VENDOR/ironic-standalone-operator" && make undeploy uninstall ) || true
else
  info "vendor/ironic-standalone-operator not present, skipping"
fi
kubectl delete ns ironic-standalone-operator-system --ignore-not-found

section "KubeVirtBMC"
kubectl delete -f https://github.com/kubevirtbmc/kubevirtbmc/releases/latest/download/kubevirtbmc-install.yaml --ignore-not-found
kubectl delete ns kubevirtbmc-system --ignore-not-found

section "CDI"
kubectl delete cdi cdi --ignore-not-found
kubectl delete ns cdi --ignore-not-found

if [[ "$KEEP_REPOS" != "true" ]]; then
  section "vendor/"
  rm -rf "$VENDOR"
  info "removed $VENDOR"
fi

section "Done"
info "cluster, KubeVirt, cert-manager, and the two patches (hotplug feature gate, StorageProfile) were left untouched"
