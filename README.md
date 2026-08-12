# metal3-kubevirtbmc-demo

Demo that provisions a Metal3 `BareMetalHost` backed by a [KubeVirt](https://kubevirt.io) VM, using [KubeVirtBMC](https://kubevirtbmc.io) as the Redfish BMC and Metal3's Ironic + Bare Metal Operator for inspection/provisioning.

## Prerequisites

- A Kubernetes cluster (e.g. `kind`) with `kubectl`, `kustomize`, and `go`/`make` available

## Usage

```bash
./setup-platform.sh   # one-time: cert-manager, KubeVirt, CDI, Ironic Standalone Operator, Ironic, Bare Metal Operator
./run-demo.sh         # configures the platform, installs KubeVirtBMC, and deploys the demo VM + BareMetalHost
```

`run-demo.sh` will:
1. Enable the KubeVirt `DeclarativeHotplugVolumes` feature gate
2. Configure the default StorageClass's StorageProfile
3. Install KubeVirtBMC and deploy a demo VM + `VirtualMachineBMC`
4. Create a `BareMetalHost` and wait for it to reach `available`

To also provision an image onto the host:

```bash
PROVISION=true ./run-demo.sh
```

Useful env vars: `setup-platform.sh` — `REFRESH_REPOS`, `IRSO_REF`, `BMO_REF`. `run-demo.sh` — `IMAGE_FORMAT` (`live-iso`|`qcow2`), `IMAGE_URL`/`IMAGE_CHECKSUM`, `STORAGE_CLASS`.

## Cleanup

```bash
./cleanup.sh
```

Removes the `BareMetalHost`, demo VM/`VirtualMachineBMC`/PVC, and KubeVirtBMC. Leaves everything installed by `setup-platform.sh` untouched.
