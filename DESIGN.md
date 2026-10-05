# Design: terraform-google-machine

Why this module looks the way it does. Each decision names the evidence it
rests on; anything not yet checked against a real project is listed under
"Unverified" and must be confirmed on the first reviewed apply.

Pins: `hashicorp/google` 8.5.0. Runtimes: Terraform >= 1.5, OpenTofu >= 1.6.
Conventions: [CONVENTIONS.md](CONVENTIONS.md). Contract:
<https://captf.io/docs/module-author/contract/v1alpha1/>.

Provider facts below were read from the provider at the pin: the schema
(`hack/tf-run.sh schema`) for attribute names and types, and the source at
`v8.5.0` (`google/services/compute/*.go`) for ForceNew, defaults, diff
suppression and API calls.

The CAPTF Google Cloud modules are three repositories, one for each role:
[terraform-google-cluster](https://github.com/captf-io/terraform-google-cluster),
[terraform-google-machine](https://github.com/captf-io/terraform-google-machine) and
[terraform-google-machinepool](https://github.com/captf-io/terraform-google-machinepool). This file covers the `machine` role and
the decisions shared with the others. Decision and Unverified numbers are the
same in all three repositories, so "decision 4" means the same everywhere; a
decision that concerns another role is a one-line pointer under its number.

## Scope

- One role here, `machine`. The other roles are the other two repositories ([cluster](https://github.com/captf-io/terraform-google-cluster), [machinepool](https://github.com/captf-io/terraform-google-machinepool)).
- Bring-your-own network: the VPC, subnetwork, proxy-only subnet and Cloud
  NAT exist before the cluster. The cluster role creates firewall rules, the
  API load balancer and node service accounts.
- The API load balancer is internal by default; external is opt-in with an
  explicit allowed-CIDR list.
- Node service accounts are created by default; variables take existing
  ones.

## Decisions

### 1. API load balancer: proxy, not passthrough

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#1-api-load-balancer-proxy-not-passthrough).

### 2. Firewall rules target service accounts

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#2-firewall-rules-target-service-accounts).

### 3. Node identities

Concerns the cluster role: see [terraform-google-cluster DESIGN.md](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#3-node-identities).

### 4. Machine

- `google_compute_instance`, Shielded VM (secure boot configurable, vTPM
  and integrity monitoring on), OS Login on, project SSH keys blocked,
  serial port off, no external IP, `cloud-platform` scope with the node
  service account.
- cloud-config (plain or gzip): metadata `user-data = var.bootstrap_data`
  plus `user-data-encoding = base64`; cloud-init's GCE datasource decodes
  it (`DataSourceGCE.py`) and decompresses gzip. Ignition reads
  `user-data` raw, so it is decoded inline in the conditional; gzipped
  Ignition fails a precondition. Metadata values are limited to 256 KB.
- `boot_disk.initialize_params.image` is ForceNew and is read back as the
  concrete image; the provider's `DiskImageDiffSuppress` cannot match a
  family name once the family has moved on ("If the config specifies a
  family name that doesn't match the image name, then the diff won't be
  properly suppressed", `resource_compute_instance.go`). The machine is
  immutable, so the image is in `ignore_changes`: a drift check never
  reports a replacement for a family's newer image.
- Control-plane machines join the zone's instance group with
  `google_compute_instance_group_membership`, with `replace_triggered_by` on
  the instance's `instance_id`: the provider docs recommend replacing the
  membership with the instance, and the self link of a replaced instance
  does not change. The membership takes the group's name, project and zone
  (the provider builds the API URL from `{{instance_group}}`), parsed from
  the exported self link. GCP cannot register an instance before it exists;
  Terraform adds it seconds after creation, well inside kubeadm's wait.
- Control-plane cloud-config payloads, which hold the cluster's CA and
  service-account keys, are staged in Secret Manager: instance metadata is
  readable through `compute.instances.get` (in `roles/viewer` and
  `roles/compute.viewer`) and the metadata server, and the control-planes
  checklist says key material MUST stay out of it. Per machine, in its own
  state: a secret replicated in the cluster's region, a version holding
  `bootstrap_data` (`is_secret_data_base64`, so gzip survives) and a
  resource-level `secretAccessor` binding for the control-plane service
  account only. `user-data` is a plain `#cloud-boothook` script, its
  install tail shared with the other CAPTF modules, that fetches the version with
  `curl` and the metadata server's token, decodes and gunzips it, refuses
  anything but cloud-config YAML (or a Jinja template of it), and writes it
  atomically (0600) to `/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg`.
  Stock cloud-init consumes user-data (boothooks included) and then resets
  its cached config (`stages.py` `_reset()` after `consume_data`), so the
  config stages read the new file; a `## template: jinja` file is rendered
  (`util.py`). CAPA's pattern, a boothook plus an `x-include-url` of a
  `file://` URL, fails on stock cloud-init: includes are resolved in
  `init.update()` (`user_data.py` `_do_include`) before boothooks run, and
  with `ERROR_ON_USER_DATA_FAILURE` the missing file aborts init (CAPA
  #2757, #4745, #5115; it works there through image-builder patches). As
  system config the payload is merged as dictionaries with lists replaced
  and `merge_how` ignored, and the file stays on disk. The instance
  `depends_on` the binding, and the stub retries for five minutes to cover
  IAM propagation. Ignition cannot authenticate the fetch, so its payload
  stays inline (this README's Exception); workers carry only a
  short-lived join token and stay inline; `bootstrap_delivery = "inline"`
  opts out for images without `curl`. A secret version holds at most 64
  KiB, checked by a precondition.
- Spot: `provisioning_model = "SPOT"`, `instance_termination_action =
  "STOP"`, so a preempted node reports `stopped` at once.
- Failure domain null: `zones[sha256(machine_name) mod n]`.

### 5. Machine pool

Concerns the machinepool role: see [terraform-google-machinepool DESIGN.md](https://github.com/captf-io/terraform-google-machinepool/blob/main/DESIGN.md#5-machine-pool).

### 6. provider_id, addresses, health

- `gce://<project>/<zone>/<instance-name>`: cloud-provider-gcp v37.1.1
  `InstanceID` returns `<project>/<zone>/<name>` and `GetInstanceProviderID`
  prefixes `gce://`; `providerIDRE` is `^gce://([^/]+)/([^/]+)/([^/]+)$`
  (`providers/gce/gce_instances.go`, `gce_util.go`). Node names equal
  instance names.
- Addresses: InternalIP (`network_ip`) and ExternalIP when an access config
  exists. That is all the controller manager reports
  (`nodeAddressesFromInstance` in `gce_instances.go` v37.1.1); the earlier
  design's Hostname address is dropped.
- Health from `current_status`, every value of the v1 `Instance.status`
  enum: RUNNING → running; PENDING, PROVISIONING, STAGING → pending;
  PENDING_STOP, STOPPING, STOPPED, SUSPENDING, SUSPENDED, TERMINATED (GCP's
  word for stopped) → stopped; REPAIRING → degraded; DEPROVISIONING ("The
  instance is halted and we are performing tear down tasks like network
  deprogramming, releasing quota, IP, tearing down disks", Compute API) →
  terminated (reason `InstanceNotFound`); other → unknown (`UnknownState`).
  An instance that no longer exists is terminated (`InstanceNotFound`). Control-plane machines refuse `spot`. The instance is `count = 1`: after an
  out-of-band delete, `apply -refresh-only` reads an empty tuple, where the
  references of a single resource would turn unknown and the outputs null;
  outputs read them through splats, because `one()` of the whole object
  would carry the sensitivity of its metadata into every output.

### 7. Labels

GCP label keys match `[a-z][a-z0-9_-]{0,62}` and values `[a-z0-9_-]{0,63}`:
no `.` or `/`. Mapping: lowercase, `.` to `-`, other invalid characters to
`_` (`captf.io/cluster` → `captf-io_cluster`); values lowercased, invalid
characters to `_`, longer than 63 characters cut to 54 plus `-` plus 8 hex
characters of the original's sha256. An empty `captf.io/template` stays
empty.

Labels are set explicitly on every labelable resource and on nested
labels (boot disk, `all_instances_config.labels`), never through provider
`default_labels`; `add_terraform_attribution_label = false`, so the labels
on a resource are exactly the documented ones. Not labelable in 8.5.0:
firewall rules, backend services, health checks, target proxies, unmanaged
instance groups, managed instance groups, autoscalers, service accounts and
IAM members.

Their descriptions name the owning object (`CAPTF cluster <ns>/<name>`),
never `captf_tags`: `description` is ForceNew on addresses, forwarding
rules, target proxies, instance groups and managed instance groups, and
`captf.io/template` changes on a ClusterClass rebase. The earlier design's
`jsonencode(var.captf_tags)` descriptions would have replaced them, the
API address included.

### 8. Credentials

Identity Secret: `GOOGLE_CREDENTIALS` (service account key JSON or an
`external_account` JSON), `GOOGLE_PROJECT`, `GOOGLE_REGION`; or a
`credentials.json` file key with
`GOOGLE_APPLICATION_CREDENTIALS=/var/run/captf/credentials/credentials.json`.
The provider block sets `project` and `region` from variables (cluster) or
exports (machine, pool); null falls back to the environment. The cluster
reads the effective values with `data.google_client_config` and fails a
postcondition when either is empty.

## Exports

A machine reads the cluster's `captf.io/gcp-cluster/v1` exports as
`captf_cluster_outputs` (or `external_cluster_exports` for an externally
managed TerraformCluster) and exports nothing. The schema, and why the
API registration targets are per-zone instance groups, are in
[DESIGN.md of terraform-google-cluster](https://github.com/captf-io/terraform-google-cluster/blob/main/DESIGN.md#exports).

## Unverified

**4.** Who can read control-plane bootstrap data that still goes in instance
metadata (Ignition, or `bootstrap_delivery = "inline"`): the metadata
server and `compute.instances.get`; the machine README lists
mitigations. Staged `cloud-config` data is covered by 9 and 10.

**5.** That DEPROVISIONING appears only while an instance is deleted, not while
it stops; a stopping pool member in that state would leave
`provider_id_list` early.

**9.** The staged bootstrap fetch on a real image: `curl`, `sed`, `base64` and
`gzip` on image-builder's GCP images, and IAM propagation of the secret
binding within the stub's five minutes of retries.

**10.** Secret Manager specifics: user-managed replication in the cluster's
region under an organization's resource-location policy, no CMEK for the
secret, and the secret's deletion when the machine is destroyed.

**11.** That a kubeadm payload behaves the same as system config as it does as
user-data: system-config merging replaces lists (`runcmd`,
`write_files`) that the image's `cloud.cfg` or another `cloud.cfg.d`
file also sets, and ignores `merge_how`.

Items 1-3, 6-8 concern the cluster and machinepool roles; see their DESIGN.md.

## Rejected alternatives

- Provider `default_labels` (misses nested labels; untestable).
- Resolving the machine image with a data source (a family's next image
  would plan a replacement on every drift check).
