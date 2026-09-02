set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$ROOT/manifests"
VENDOR="$ROOT/vendor"

REFRESH_REPOS="${REFRESH_REPOS:-false}"
IRSO_REF="${IRSO_REF:-}"
BMO_REF="${BMO_REF:-}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.1}"
KUBEVIRT_VERSION="${KUBEVIRT_VERSION:-v1.9.0}"

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

clone_repo() {
  local url=$1 dir=$2 ref=$3
  if [[ -d "$dir/.git" ]]; then
    if [[ "$REFRESH_REPOS" == "true" ]]; then
      git -C "$dir" fetch --all --tags
      [[ -n "$ref" ]] && git -C "$dir" checkout "$ref"
    else
      info "$(basename "$dir") already cloned, leaving as-is (set REFRESH_REPOS=true to update)"
    fi
  else
    git clone "$url" "$dir"
    [[ -n "$ref" ]] && git -C "$dir" checkout "$ref"
  fi
}

install_metal3() {
  section "Ironic Standalone Operator"
  mkdir -p "$VENDOR"
  clone_repo https://github.com/metal3-io/ironic-standalone-operator.git \
    "$VENDOR/ironic-standalone-operator" "$IRSO_REF"
  ( cd "$VENDOR/ironic-standalone-operator" && make install deploy )
  kubectl -n ironic-standalone-operator-system wait --for=condition=Available \
    deploy/ironic-standalone-operator-controller-manager --timeout=180s

  section "Ironic"
  kubectl create ns baremetal-operator-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$MANIFESTS/03-ironic-certs.yaml"
  kubectl apply -f "$MANIFESTS/04-ironic-credentials.yaml"
  kubectl apply -f "$MANIFESTS/05-ironic.yaml"
  kubectl -n baremetal-operator-system wait --for=condition=Ready ironic/ironic --timeout=300s

  section "Bare Metal Operator"
  clone_repo https://github.com/metal3-io/baremetal-operator.git \
    "$VENDOR/baremetal-operator" "$BMO_REF"
  local bmo="$VENDOR/baremetal-operator"
  mkdir -p "$bmo/config/overlays/kubevirtbmc-demo"
  cp "$MANIFESTS/bmo-overlay-kustomization.yaml" "$bmo/config/overlays/kubevirtbmc-demo/kustomization.yaml"
  cp "$MANIFESTS/bmo-ironic.env" "$bmo/config/default/ironic.env"
  ( cd "$bmo" && kustomize build config/overlays/kubevirtbmc-demo | kubectl apply -f - )
  kubectl -n baremetal-operator-system wait --for=condition=Available \
    deploy/baremetal-operator-controller-manager --timeout=180s
}

summary() {
  section "Done"
  info "Platform installed: cert-manager, KubeVirt, CDI, Ironic Standalone Operator, Ironic, Bare Metal Operator"
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
