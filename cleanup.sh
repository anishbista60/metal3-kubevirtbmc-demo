set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="$ROOT/manifests"

BOLD=$'\033[1m'; CYAN=$'\033[36m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
section() { printf '\n%s%s== %s ==%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }
info()    { printf '%s -> %s%s\n' "$GREEN" "$1" "$RESET"; }

section "BareMetalHost"
kubectl delete -f "$MANIFESTS/06-bmh.yaml" --ignore-not-found

section "Demo VM + VirtualMachineBMC"
kubectl delete -f "$MANIFESTS/02-vm-bmc.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/01-vm.yaml" --ignore-not-found
kubectl delete -f "$MANIFESTS/00-vm-pvc.yaml" --ignore-not-found

section "KubeVirtBMC"
kubectl delete -f https://github.com/kubevirtbmc/kubevirtbmc/releases/latest/download/kubevirtbmc-install.yaml --ignore-not-found

section "Done"
info "platform components (installed via setup-platform.sh) were left untouched"
