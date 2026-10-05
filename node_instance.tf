# Copyright 2026 The CAPTF Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The node: one Shielded VM with no external IP, running as the cluster's
# node service account, booted by cloud-init or Ignition from instance
# metadata (DESIGN.md decision 4). The role's primary resource.
resource "google_compute_instance" "node_instance" {
  # count = 1, not a single resource: after an out-of-band delete a refresh
  # reads an empty tuple rather than an unknown, so health reports terminated.
  count = 1

  can_ip_forward = var.can_ip_forward
  description    = local.description
  labels         = local.tags
  machine_type   = var.machine_type
  # OS Login instead of metadata SSH keys, project-wide keys blocked, no
  # interactive serial console (CONVENTIONS.md section 8), and the payload.
  metadata = merge({
    "block-project-ssh-keys" = "TRUE"
    "enable-oslogin"         = "TRUE"
    "serial-port-enable"     = "FALSE"
  }, local.user_data_metadata)
  name    = local.instance_name
  project = local.project
  tags    = local.network_tags
  zone    = local.zone

  boot_disk {
    auto_delete       = true
    kms_key_self_link = var.boot_disk_kms_key_id

    initialize_params {
      image  = local.image
      labels = local.tags
      size   = var.boot_disk_size_gib
      type   = var.boot_disk_type
    }
  }

  # No access_config: no external IP. Nodes reach the internet through the
  # Cloud NAT of the network you bring.
  network_interface {
    stack_type = "IPV4_ONLY"
    subnetwork = local.subnetwork
  }

  # Spot VMs stop when preempted (instance_termination_action), so a
  # preempted node reports stopped at once and its disk survives.
  scheduling {
    automatic_restart           = !var.spot
    instance_termination_action = var.spot ? "STOP" : null
    on_host_maintenance         = var.spot ? "TERMINATE" : "MIGRATE"
    preemptible                 = var.spot
    provisioning_model          = var.spot ? "SPOT" : "STANDARD"
  }

  # cloud-platform scope: access is decided by the account's IAM roles, the
  # way Google recommends (https://cloud.google.com/compute/docs/access/service-accounts#scopes_best_practice).
  service_account {
    email  = local.service_account
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = var.secure_boot
    enable_vtpm                 = true
  }

  lifecycle {
    # The image is a create-time property of an immutable machine. A family
    # name resolves to whatever image is newest, which the provider's diff
    # cannot match after the family moves on, so drift would report a
    # replacement forever (DiskImageDiffSuppress in the provider).
    ignore_changes = [boot_disk[0].initialize_params[0].image]

    precondition {
      condition     = !(var.control_plane && var.spot)
      error_message = "spot must be false for a control-plane machine: a preempted control-plane node takes an etcd member with it (CONVENTIONS.md section 11)."
    }
    precondition {
      condition     = local.cluster_exports != null
      error_message = "The TerraformCluster is externally managed (captf_cluster_outputs is {}): set spec.template.spec.variables.external_cluster_exports on the TerraformMachineTemplate to exports of schema captf.io/gcp-cluster/v1."
    }
    precondition {
      condition     = local.zone != null && contains(local.failure_domains, coalesce(local.zone, "-"))
      error_message = "failure_domain ${coalesce(var.failure_domain, "(none)")} is not a failure domain of the cluster; use one of: ${join(", ", local.failure_domains)}."
    }
    precondition {
      condition     = !(var.bootstrap_format == "ignition" && local.bootstrap_gzipped)
      error_message = "A gzipped Ignition payload is not supported: Ignition reads GCE user-data uncompressed. Turn off gzipUserData in the bootstrap config."
    }
    precondition {
      condition     = !local.bootstrap_staged || local.bootstrap_bytes <= local.secret_max_bytes
      error_message = "The control-plane bootstrap payload is ${nonsensitive(local.bootstrap_bytes)} bytes, over Secret Manager's ${local.secret_max_bytes}-byte limit: gzip it, or set spec.template.spec.variables.bootstrap_delivery to inline."
    }
    precondition {
      condition     = length(local.user_data) <= local.user_data_max_bytes
      error_message = "The bootstrap payload is ${nonsensitive(length(local.user_data))} bytes as user-data, over the ${local.user_data_max_bytes}-byte metadata value limit: gzip it (cloud-config) or shrink it."
    }
    precondition {
      condition     = !local.image_has_placeholder || local.kubernetes_semver != null
      error_message = "image ${coalesce(var.image, "-")} holds a {version}, {semver}, {slug} or {fullslug} placeholder but the Machine has no spec.version to fill it."
    }
    precondition {
      condition     = !var.control_plane || local.api_instance_groups == null || local.api_instance_group_parts != null
      error_message = "The cluster exports no API instance group for zone ${coalesce(local.zone, "-")}: a control-plane machine must be in one of the cluster's failure domains."
    }
  }

  # The stub fetches the payload at boot, so the instance must not start before
  # its service account can read the secret; nothing in the instance's
  # arguments refers to the binding.
  depends_on = [google_secret_manager_secret_iam_member.bootstrap_secret_accessor]
}
