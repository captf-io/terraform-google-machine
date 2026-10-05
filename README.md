<h1 align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="72" height="72" alt="CAPTF"></a>
  <br>
  terraform-google-machine
</h1>

<p align="center">The CAPTF machine module for Google Cloud</p>

<p align="center">
  <a href="https://github.com/captf-io/terraform-google-machine/actions/workflows/ci.yml"><img
    src="https://img.shields.io/github/actions/workflow/status/captf-io/terraform-google-machine/ci.yml?branch=main&amp;label=build&amp;labelColor=161B3A&amp;style=flat-square"
    alt="build"></a>
  <a href="https://captf.io/docs/module-author/contract/index.html"><img
    src="https://img.shields.io/static/v1?label=contract&amp;message=v1alpha1&amp;color=A974FF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="contract v1alpha1"></a>
  <a href="https://captf.io/docs/"><img
    src="https://img.shields.io/static/v1?label=docs&amp;message=captf.io&amp;color=5B8CFF&amp;labelColor=161B3A&amp;style=flat-square"
    alt="docs captf.io"></a>
  <a href="https://github.com/captf-io/terraform-google-machine/blob/main/LICENSE.md"><img
    src="https://img.shields.io/static/v1?label=license&amp;message=Apache-2.0&amp;color=FFD84D&amp;labelColor=161B3A&amp;style=flat-square"
    alt="license Apache-2.0"></a>
</p>

> [!NOTE]
> **Pre-release.** CAPTF is `v1alpha1`: its API and its
> [module contract](https://captf.io/docs/module-author/contract/index.html)
> may still change between releases.

The `machine` role of the CAPTF modules for Google Cloud: the
Terraform/OpenTofu root module behind `TerraformMachine`, cloned from a
`TerraformMachineTemplate`. It creates one Compute Engine instance per
Cluster API Machine, control plane or worker. Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/machine.html>.

This repository holds the module code. The image `ghcr.io/captf-io/gcp-machine`
is published from
[captf-io/gcp-modules](https://github.com/captf-io/gcp-modules).

## Using it

CAPTF runs this module from the module image `ghcr.io/captf-io/gcp-machine`: set
the image on a `TerraformMachine`'s `spec.source.image` (through a
`TerraformMachineTemplate`), and the controller renders every input. The module
is also published to the Terraform Registry as `captf-io/machine/google` and can
be called directly:

```hcl
module "machine" {
  source  = "captf-io/machine/google"
  version = "~> 0.1"

  # The contract inputs the controller would render (captf_contract,
  # captf_cluster, captf_object, captf_tags, ...; see Inputs), and any
  # user variables.
}
```

Called directly, the module is a CAPTF root module first:

- it configures its own `provider "google"` block, so the calling
  module cannot use `count`, `for_each` or `depends_on` on it, and the
  provider takes its credentials from the environment (see Identity
  Secret);
- its providers are pinned to exact versions (`versions.tf`), which the
  calling configuration has to accept;
- you set the `captf_*` inputs yourself.

## What it creates

| Resource | Type | When |
| --- | --- | --- |
| `node_instance` | `google_compute_instance` | Always: a Shielded VM with no external IP, running as the cluster's control-plane or worker service account, booted from instance metadata |
| `api_instance_group_membership` | `google_compute_instance_group_membership` | Control-plane machines of a cluster with a module-owned endpoint: joins the API instance group of the instance's zone |
| `bootstrap_secret` | `google_secret_manager_secret` | Control-plane machines with a cloud-config payload and `bootstrap_delivery = "secret-manager"`: holds the bootstrap payload |
| `bootstrap_secret_version` | `google_secret_manager_secret_version` | Same: the payload itself |
| `bootstrap_secret_accessor` | `google_secret_manager_secret_iam_member` | Same: `roles/secretmanager.secretAccessor` for the control-plane service account on that secret only |

The membership lives in the machine's own state, so destroying the machine
deregisters it (`machine.md` "Control-plane machines"). Terraform creates it
seconds after the instance, well before `kubeadm init` or `join` needs the
endpoint. A replaced instance keeps its self link but leaves the group, so
the membership is replaced with it (`replace_triggered_by` on
`instance_id`, as the provider documentation advises).

The instance:

- runs `machine_type` (default `n2-standard-4`) from `image`, with a
  `boot_disk_size_gib` GiB `boot_disk_type` boot disk, optionally encrypted with
  `boot_disk_kms_key_id`;
- has Shielded VM with vTPM and integrity monitoring, and Secure Boot unless
  `secure_boot` is off;
- sets `enable-oslogin=TRUE`, `block-project-ssh-keys=TRUE` and
  `serial-port-enable=FALSE`;
- runs as the cluster's service account with the `cloud-platform` scope, so
  IAM roles alone decide its access;
- carries the cluster's node tag and role tag plus `additional_network_tags`;
- as a Spot VM (`spot`), stops when preempted.

## Prerequisites

- **A gcp-cluster TerraformCluster**, whose exports give the project,
  region, subnetwork, service accounts, network tags and API instance
  groups; or `external_cluster_exports` for an externally managed one.
- **A node image** with the Kubernetes components and cloud-init (cloud-config
  bootstrap; `curl`, `sed`, `base64` and `gzip` for staged control-plane
  payloads) or Ignition, for example one built by
  [image-builder](https://image-builder.sigs.k8s.io/capi/providers/gcp). Its
  kernel modules must be signed for Secure Boot.
- **A cloud controller manager**: the module's `provider_id` is what
  [cloud-provider-gcp](https://github.com/kubernetes/cloud-provider-gcp)
  writes to `Node.spec.providerID`. Run the kubelet with
  `cloud-provider: external` and deploy cloud-provider-gcp with `gce.conf`
  values from the cluster's exports (`project-id`, `network-name`,
  `subnetwork-name`, `node-tags = <node_network_tag>`). Without a CCM, set
  the kubelet's `provider-id` to the same `gce://` value yourself.
- **Quotas**: CPUs of `machine_type`'s family in the region, persistent disk
  of `boot_disk_type`; Spot quota for `spot`.
- **The Secret Manager API** enabled in the project, for staged
  control-plane payloads.
- **Permissions of the identity**: see the role table in the
  [cluster README](https://github.com/captf-io/terraform-google-cluster#prerequisites);
  `roles/cloudkms.cryptoKeyEncrypterDecrypter` for the Compute Engine
  service agent on `boot_disk_kms_key_id`.

## Inputs

Contract inputs used: `machine_name` (the instance name), `bootstrap_data`
and `bootstrap_format` (user-data), `failure_domain` (the zone),
`kubernetes_version` (image placeholders), `control_plane` (service account,
tags, API registration), `captf_cluster_outputs` (exports), `captf_cluster`
and `captf_object` (descriptions), `captf_tags` (labels). `captf_contract`
is validated.

User variables (`TerraformMachineTemplate.spec.template.spec.variables`):

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `additional_network_tags` | `list(string)` | `[]` | Extra network tags for the instance, on top of the cluster's node and role tags. |
| `additional_tags` | `map(string)` | `{}` | Extra GCP labels for the instance and its boot disk. Keys and values must already be valid GCP labels; the captf-io_ keys are reserved for captf_tags, which win. |
| `boot_disk_kms_key_id` | `string` | `null` | Cloud KMS key (projects/.../cryptoKeys/...) that encrypts the boot disk. Null uses Google-managed encryption; the Compute Engine service agent needs encrypt and decrypt on the key. |
| `boot_disk_size_gib` | `number` | `50` | Boot disk size in GiB: room for the image, container images and logs. |
| `boot_disk_type` | `string` | `"pd-balanced"` | Boot disk type. pd-balanced suits the default N2 machine type; C3, N4 and newer series need hyperdisk-balanced. |
| `bootstrap_delivery` | `string` | `"secret-manager"` | How a control-plane machine's cloud-config payload reaches it. secret-manager (default) stages it in a per-machine secret behind a small user-data stub, which needs curl, sed, base64 and gzip in the image; inline puts it in instance metadata, where compute.instances.get and the metadata server expose the cluster's CA keys. Workers and Ignition are always inline. |
| `can_ip_forward` | `bool` | `false` | Let the instance send and receive packets for other addresses, as CNIs that route pod CIDRs through GCP routes need. Off by default. |
| `external_cluster_exports` | `any` | `null` | Exports (schema captf.io/gcp-cluster/v1) to use when the TerraformCluster is externally managed and captf_cluster_outputs is {}. Ignored otherwise. |
| `image` | `string` | `null` | Boot image: a name, family/<family>, projects/<p>/global/images/<image> or a self link. {version}, {semver}, {slug} and {fullslug} are replaced by v1.33.4, 1.33.4, v1-33-4 and v1-33-4-rke2r1 (suffix kept) from kubernetes_version. Required. |
| `machine_type` | `string` | `"n2-standard-4"` | Machine type of the instance. The default matches the image's io.captf.capacity label (4 vCPU, 16 GiB). |
| `secure_boot` | `bool` | `true` | Shielded VM Secure Boot. On by default; turn it off only for images whose kernel modules are unsigned (some GPU drivers). |
| `spot` | `bool` | `false` | Run as a Spot VM: cheaper, preemptible at any time; a preempted instance stops and reports stopped. Off by default. |

`image` placeholders: `{version}` is `v1.33.4`, `{semver}` `1.33.4` and
`{slug}` `v1-33-4`, all without a `+rke2rN` suffix; `{fullslug}` keeps it,
`v1-33-4-rke2r1` (image names allow no dots or `+`).

## Outputs

| Name | Value |
| --- | --- |
| `provider_id` | `gce://<project>/<zone>/<instance name>` |
| `addresses` | `InternalIP` of the NIC, and `ExternalIP` if an access config exists (never, as created) |
| `failure_domain` | The instance's zone: the requested `failure_domain`, or the module's pick |
| `interruptible` | `true` for a Spot VM |
| `health` | Below |

`provider_id` is the format cloud-provider-gcp writes and parses:
`providerIDRE` `^gce://([^/]+)/([^/]+)/([^/]+)$` in
[`providers/gce/gce_util.go`](https://github.com/kubernetes/cloud-provider-gcp/blob/v37.1.1/providers/gce/gce_util.go).
The CCM reports a node's InternalIP and ExternalIP from the instance's NICs
(`nodeAddressesFromInstance` in
[`providers/gce/gce_instances.go`](https://github.com/kubernetes/cloud-provider-gcp/blob/v37.1.1/providers/gce/gce_instances.go)),
and `addresses` mirrors it.

Non-contract outputs: `api_instance_group_membership_id`, `instance_id`,
`instance_self_link`.

## Exports

Reads the cluster's `captf.io/gcp-cluster/v1` exports (see
[the cluster README](https://github.com/captf-io/terraform-google-cluster#exports)); exports nothing. A
`captf_cluster_outputs` of another schema fails validation. `{}` (an
externally managed TerraformCluster) needs `external_cluster_exports`, else
the plan fails with instructions.

## Identity Secret

The same Secret as the cluster role: `GOOGLE_CREDENTIALS` (or
`GOOGLE_APPLICATION_CREDENTIALS` and a file key). The project and region come
from the exports, not from `GOOGLE_PROJECT` and `GOOGLE_REGION`. See
[examples/identity.yaml](https://github.com/captf-io/terraform-google-machine/blob/main/examples/identity.yaml).

## Bootstrap

| Machine | `bootstrap_format` | Payload | Sent as |
| --- | --- | --- | --- |
| control plane, `bootstrap_delivery = "secret-manager"` (default) | `cloud-config` | plain or gzipped | staged in a per-machine Secret Manager secret; `user-data` holds a small stub (below) |
| worker, or `bootstrap_delivery = "inline"` | `cloud-config` | plain or gzipped | `bootstrap_data` unchanged (base64) with `user-data-encoding=base64`: cloud-init's GCE datasource decodes it, then decompresses gzip |
| any | `ignition` | plain | decoded in `user-data`: Ignition reads it as it is |
| any | `ignition` | gzipped | refused by a precondition: Ignition does not decompress GCE user-data |

**Control-plane payloads are staged.** They embed the cluster's CA and
service-account keys, and instance metadata is readable through
`compute.instances.get` (in basic `roles/viewer` and in `roles/compute.viewer`)
and by anything on the node that reaches the metadata server. So the module
writes the payload to a secret (`<instance>-<zone>-bootstrap`, replicated in
the cluster's region, labelled), grants only the control-plane service
account `roles/secretmanager.secretAccessor` on that one secret, and puts a
stub in `user-data`: a plain `#cloud-boothook` script that takes the instance's token from the
metadata server, reads the secret version over the Secret Manager REST API
with `curl`, decodes and gunzips it (`sed`, `base64`, `gzip`), and writes it
atomically, mode 0600, to `/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg`.
cloud-init runs boothooks while it consumes user-data and re-reads its system
config afterwards, before the config modules run, so they run the payload on
stock cloud-init; a `## template: jinja` payload (what kubeadm writes) is
rendered there too. The stub retries for five minutes, covering the
binding's IAM propagation. Destroying the machine deletes the secret.

What this means for the payload:

- It must be cloud-config YAML (or a Jinja template of it). A MIME or shell
  payload is refused, with a `captf:` line in the cloud-init log, since
  system config would silently ignore it.
- It is merged as system config: dictionaries merge, lists replace earlier
  ones, and `merge_how` is ignored. A key that the image's own `cloud.cfg`
  or an earlier `cloud.cfg.d` file also sets (for example `runcmd`) is
  replaced, not appended to.
- The file stays on disk, readable by root only.

Images without `curl` need `bootstrap_delivery = "inline"`. An `x-include-url`
part, the pattern Cluster API Provider AWS uses, does not work on stock
cloud-init: it resolves includes before boothooks run, so the file does not
exist yet and init aborts.

A pod that can reach the metadata server can still take the node's token and
read the secret: block pod egress to `169.254.169.254` with a NetworkPolicy or
your CNI's global policy, except for the system components that need it.

Limits: a secret version holds at most 64 KiB and a metadata value 256 KB;
a larger payload fails a precondition. Gzip it (CAPRKE2 `gzipUserData`).

## Tags

The instance and its boot disk carry `merge(additional_tags, captf_tags)` as
GCP labels, with the mapping of the [cluster README](https://github.com/captf-io/terraform-google-cluster#tags)
(`captf.io/cluster` becomes `captf-io_cluster`). The instance group
membership cannot carry labels.

## Health

From the instance's `current_status`, re-read on every refresh:

| Status | `state` | `healthy` | `reasons` |
| --- | --- | --- | --- |
| `RUNNING` | `running` | `true` | `[]` |
| `PENDING`, `PROVISIONING`, `STAGING` | `pending` | `false` | `InstancePending`, `InstanceProvisioning`, `InstanceStaging` |
| `REPAIRING` | `degraded` | `false` | `InstanceRepairing` |
| `PENDING_STOP`, `STOPPING`, `STOPPED`, `SUSPENDING`, `SUSPENDED`, `TERMINATED` | `stopped` | `false` | `Instance<Status>`, e.g. `InstanceTerminated` |
| `DEPROVISIONING` | `terminated` | `false` | `InstanceNotFound` |
| anything else | `unknown` | `false` | `UnknownState` |
| the instance no longer exists | `terminated` | `false` | `InstanceNotFound` |

`TERMINATED` is Compute Engine's word for stopped: the instance and its disk
still exist. A preempted Spot VM is `TERMINATED`, so it reports `stopped`
and a MachineHealthCheck can replace it.

## Limitations

- The instance name is the Node name, because cloud-provider-gcp looks
  instances up by Node name: `machine_name` when it is a valid Compute
  Engine name, else `machine_name` with invalid characters replaced, a
  leading `m-` if needed, cut to 54 characters, plus `-` and 8 hex characters
  of its sha256. Instance names are unique per project and zone, so two
  Machines of the same name in different namespaces collide in a shared
  project.
- The image is a create-time property: `ignore_changes` keeps a drift check
  from reporting a family's newer image as a replacement. Roll a new image
  through a new TerraformMachineTemplate.
- Control-plane machines refuse `spot`: a preempted control-plane node
  takes an etcd member with it.
- A failure domain must be one of the cluster's zones; a control-plane
  machine's zone must have an API instance group.

## Exceptions

- **Ignition control-plane payloads stay in instance metadata.** The
  control-planes checklist says a machine module MUST keep key material out
  of readable instance metadata ("CP bootstrap payload size and secrecy").
  Ignition cannot run the stub's authenticated fetch from Secret Manager, so
  an Ignition payload goes inline, exposed to `compute.instances.get` and the
  metadata server. `bootstrap_delivery = "inline"` makes the same trade for
  cloud-config on images without `curl`. Restrict `compute.instances.get`
  and block pod access to the metadata server.

## Examples

A TerraformMachineTemplate with this image (from
[examples/cluster-kubeadm.yaml](https://github.com/captf-io/terraform-google-machine/blob/main/examples/cluster-kubeadm.yaml)):

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1alpha1
kind: TerraformMachineTemplate
metadata:
  name: demo-md-0
spec:
  template:
    spec:
      source:
        image: ghcr.io/captf-io/gcp-machine:v0.1.0-opentofu
      variables:
        image: projects/my-images/global/images/capi-ubuntu-2404-{slug}
```

## Developing

The host needs make, podman (or docker with `ENGINE=docker`), jq and Go.
Every other tool runs in a digest-pinned container. `make verify` is the
gate. `make help` lists the targets:

- `make fmt`: format the module with `terraform fmt` and `tofu fmt`, in place.
- `make fmt-check`: fail on any file the formatters would change.
- `make validate`: `init` and `validate` on both runtimes and on their floors
  (Terraform 1.5.7, OpenTofu 1.6.3).
- `make unit-test`: `terraform test` and `tofu test` with mocked providers.
- `make tflint`: tflint with the terraform ruleset (preset all) and the cloud
  ruleset.
- `make tfcapi-lint`: `tfcapi-lint module --strict`, built from `PROVIDER_DIR`
  (default `../cluster-api-provider-terraform`, a clone of
  [cluster-api-provider-terraform](https://github.com/captf-io/cluster-api-provider-terraform)
  next to this one); skipped when it is absent.
- `make scan`: trivy config over the repository; ignores live in
  `.trivyignore.yaml`.
- `make check-conventions`: the layout and tag checks (`hack/check-layout.sh`,
  `hack/check-tags.sh`) for CONVENTIONS.md.
- `make shellcheck`: shellcheck over `hack/` and every shell template.
- `make check-headers`, `make fix-headers`: check or add the Apache-2.0 license
  header.
- `make verify`: all of the above, in parallel groups.
- `make clean`: remove `build/`; keeps `.cache/` and `.tools/`.

Useful variables: `RUNTIMES=opentofu` (or `terraform`), `ENGINE=docker`,
`PROVIDER_DIR=<path>`.

<br>
<p align="center">
  <img
    src="https://captf.io/assets/readme/divider.svg"
    width="100%" height="4" alt="">
</p>
<p align="center">
  <a href="https://captf.io/"><img
    src="https://captf.io/assets/readme/mark.svg"
    width="40" height="40" alt="CAPTF"></a>
  <br>
  <a href="https://captf.io/docs/"
    ><b>Documentation</b></a> ·
  <a href="https://captf.io/docs/getting-started/quick-start.html"
    ><b>Quick start</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/CONTRIBUTING.md"
    ><b>Contributing</b></a> ·
  <a href="https://github.com/captf-io/.github/blob/main/SECURITY.md"
    ><b>Security</b></a>
  <br>
  <sub>Built for
    <a href="https://cluster-api.sigs.k8s.io/">Cluster API</a>.
    <a href="https://github.com/captf-io/terraform-google-machine/blob/main/LICENSE.md"
    >Apache 2.0</a>.</sub>
</p>
