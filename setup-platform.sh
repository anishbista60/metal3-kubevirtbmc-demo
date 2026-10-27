set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$ROOT/manifests"

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.1}"
KUBEVIRT_VERSION="${KUBEVIRT_VERSION:-v1.9.0}"
IRSO_VERSION="${IRSO_VERSION:-v0.12.0}"
BMO_VERSION="${BMO_VERSION:-v0.14.1}"

# true  = Ironic serves virtual media over HTTPS; KubeVirtBMC/CDI trust Ironic's CA
#         through VirtualMachineBMC.spec.redfish.virtualMedia.tls (KubeVirtBMC >= v0.11.0)
# false = virtual media over plain HTTP
VIRTUAL_MEDIA_TLS="${VIRTUAL_MEDIA_TLS:-true}"

BOLD=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

section() { printf '\n%s%s== %s ==%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
info()    { printf '%s -> %s%s\n' "$GREEN" "$1" "$RESET"; }
warn()    { printf '%s !! %s%s\n' "$YELLOW" "$1" "$RESET"; }

trap 'echo; warn "Failed at line $LINENO. Fix the cause and re-run ./setup-platform.sh — steps are idempotent."; exit 1' ERR

latest_tag() {
  curl -sL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'
}

install_cert_manager() {
  section "cert-manager"
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
}

install_kubevirt() {
  section "KubeVirt"
  kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
  kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-cr.yaml"
  kubectl -n kubevirt wait --for=condition=Available kubevirt/kubevirt --timeout=300s
}

install_cdi() {
  section "CDI (Containerized Data Importer)"
  local version
  version="$(latest_tag kubevirt/containerized-data-importer)"
  kubectl apply -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-operator.yaml"
  kubectl apply -f "https://github.com/kubevirt/containerized-data-importer/releases/download/${version}/cdi-cr.yaml"
  kubectl wait --for=condition=Available cdi/cdi --timeout=300s
}

# retry <description> <timeout-seconds> <cmd>: re-runs cmd every 5s until it succeeds.
retry() {
  local desc=$1 timeout=$2 cmd=$3 start
  start=$(date +%s)
  until eval "$cmd"; do
    (( $(date +%s) - start > timeout )) && { warn "timed out waiting for $desc"; return 1; }
    info "waiting for $desc"
    sleep 5
  done
}

install_metal3() {
  section "Ironic Standalone Operator $IRSO_VERSION"
  kubectl apply -f "https://github.com/metal3-io/ironic-standalone-operator/releases/download/${IRSO_VERSION}/install.yaml"
  kubectl -n ironic-standalone-operator-system wait --for=condition=Available \
    deploy/ironic-standalone-operator-controller-manager --timeout=300s

  section "Ironic"
  kubectl create ns baremetal-operator-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$MANIFESTS/03-ironic-certs.yaml"
  kubectl apply -f "$MANIFESTS/04-ironic-credentials.yaml"
  kubectl -n baremetal-operator-system wait --for=condition=Ready certificate/ironic-cert --timeout=120s
  local ironic_cr="$MANIFESTS/05-ironic-vmedia-tls.yaml"
  [[ "$VIRTUAL_MEDIA_TLS" == "true" ]] || ironic_cr="$MANIFESTS/05-ironic-vmedia-http.yaml"
  info "Ironic CR: $(basename "$ironic_cr")"
  # The IrSO webhook can take a moment to start answering after the deployment is Available.
  retry "Ironic CR accepted" 120 "kubectl apply -f '$ironic_cr'"
  kubectl -n baremetal-operator-system wait --for=condition=Ready ironic/ironic --timeout=600s

  section "Bare Metal Operator $BMO_VERSION"
  kubectl apply -f "https://github.com/metal3-io/baremetal-operator/releases/download/${BMO_VERSION}/baremetal-operator.yaml"
  # Instead of an endpoint + CA file, point BMO at the Ironic CR — it reads the
  # URL, credentials and CA from it. Same as upstream's config/use-irso overlay.
  kubectl -n baremetal-operator-system create configmap ironic \
    --from-literal=IRONIC_NAME=ironic --dry-run=client -o yaml | kubectl replace -f -
  kubectl -n baremetal-operator-system rollout restart deploy/baremetal-operator-controller-manager
  kubectl -n baremetal-operator-system rollout status deploy/baremetal-operator-controller-manager --timeout=300s
}

summary() {
  section "Done"
  info "Platform installed: cert-manager, KubeVirt, CDI, Ironic Standalone Operator, Ironic, Bare Metal Operator"
  info "Virtual media TLS: $VIRTUAL_MEDIA_TLS"
  info "Next: ./run-demo.sh"
}

main() {
  install_cert_manager
  install_kubevirt
  install_cdi
  install_metal3
  summary
}

main "$@"
