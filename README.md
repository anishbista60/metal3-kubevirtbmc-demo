# metal3-kubevirtbmc-demo

Demo that provisions a Metal3 `BareMetalHost` backed by a [KubeVirt](https://kubevirt.io) VM, using [KubeVirtBMC](https://kubevirtbmc.io) as the Redfish BMC and Metal3's Ironic + Bare Metal Operator for inspection/provisioning.

## Prerequisites

- A Kubernetes cluster (e.g. `kind`) with `kubectl`, `kustomize`, and `go`/`make` available
- [KubeVirt](https://kubevirt.io) and [cert-manager](https://cert-manager.io) installed — follow the [KubeVirtBMC installation guide](https://docs.kubevirtbmc.io/getting-started/#installation)

## Usage

```bash
./run-demo.sh
```

This will:
1. Enable the KubeVirt `DeclarativeHotplugVolumes` feature gate
2. Install CDI and configure the default StorageClass's StorageProfile
3. Install KubeVirtBMC and deploy a demo VM + `VirtualMachineBMC`
4. Install the Ironic Standalone Operator, Ironic, and the Bare Metal Operator
5. Create a `BareMetalHost` and wait for it to reach `available`

To also provision an image onto the host:

```bash
PROVISION=true ./run-demo.sh
```

Useful env vars: `IMAGE_FORMAT` (`live-iso`|`qcow2`), `IMAGE_URL`/`IMAGE_CHECKSUM`, `STORAGE_CLASS`, `REFRESH_REPOS`, `SKIP_CDI`, `IRSO_REF`, `BMO_REF`.

## Cleanup

```bash
./cleanup.sh          # also removes cloned vendor/ repos
./cleanup.sh --keep-repos
```

Leaves the cluster, KubeVirt, and cert-manager untouched.
