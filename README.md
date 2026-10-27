# metal3-kubevirtbmc-demo

Demo that provisions a Metal3 `BareMetalHost` backed by a [KubeVirt](https://kubevirt.io) VM, using [KubeVirtBMC](https://kubevirtbmc.io) as the Redfish BMC and Metal3's Ironic + Bare Metal Operator for inspection/provisioning.

## Prerequisites

- A `kind` cluster created from `kind-config.yaml`, and `kubectl`, `curl` available
- An x86_64 Linux host with `/dev/kvm` (the IPA ramdisk and the Ubuntu cloud image are x86_64)

## Usage

```bash
kind create cluster --config kind-config.yaml
./setup-platform.sh   # one-time: cert-manager, KubeVirt, CDI, Ironic Standalone Operator, Ironic, Bare Metal Operator
./run-demo.sh         # configures the platform, installs KubeVirtBMC, and deploys the demo VM + BareMetalHost
```

`run-demo.sh` will:
1. Enable the KubeVirt `DeclarativeHotplugVolumes` feature gate
2. Configure the default StorageClass's StorageProfile
3. Install KubeVirtBMC, copy Ironic's CA into a `ironic-ca` ConfigMap, and deploy a demo VM + `VirtualMachineBMC`
4. Start an in-cluster image server that downloads the Ubuntu 24.04 cloud image (qcow2) and generates its sha256sum
5. Create a `BareMetalHost` and wait for it to reach `available`

`setup-platform.sh` installs Metal3 from pinned release manifests, nothing is built from source:
IrSO `v0.12.0` (`install.yaml`), Ironic `39.0` (the `Ironic` CR), and BMO `v0.14.1` (`baremetal-operator.yaml`).
BMO is pointed at the `Ironic` CR (`IRONIC_NAME=ironic`) and reads its URL, credentials and CA from it.
By default virtual media is served over HTTPS (`05-ironic-vmedia-tls.yaml`); the `VirtualMachineBMC`
trusts Ironic's CA through `spec.redfish.virtualMedia.tls`, which needs KubeVirtBMC >= v0.11.0.

To also provision the Ubuntu cloud image onto the host (IPA writes the qcow2 straight to `/dev/vda`,
cloud-init from `manifests/09-bmh-userdata.yaml` sets the `ubuntu` user's password to `ubuntu`):

```bash
PROVISION=true ./run-demo.sh
```

Useful env vars: `setup-platform.sh` — `IRSO_VERSION`, `BMO_VERSION`, `VIRTUAL_MEDIA_TLS` (`true`|`false`, plain-HTTP fallback). `run-demo.sh` — `KUBEVIRTBMC_VERSION`, `IMAGE_URL` (a different qcow2 cloud image for the image server), `STORAGE_CLASS`.

## Cleanup

```bash
./cleanup.sh
```

Removes the `BareMetalHost`, demo VM/`VirtualMachineBMC`/PVC, image server, userData secret, `ironic-ca` ConfigMap, and KubeVirtBMC. The downloaded image stays cached on the kind node in `/var/lib/metal3-demo-images`. Leaves everything installed by `setup-platform.sh` untouched.
