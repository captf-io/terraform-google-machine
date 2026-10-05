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

# User variables of the machine role, set through the TerraformMachineTemplate's
# spec.template.spec.variables or variablesFrom
# (https://captf.io/docs/user-guide/variables.html). Alphabetical.

variable "additional_network_tags" {
  description = "Extra network tags for the instance, on top of the cluster's node and role tags."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.additional_network_tags : can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", t))])
    error_message = "additional_network_tags must hold tags such as allow-ssh (lowercase letters, digits and -, at most 63 characters)."
  }
}

variable "additional_tags" {
  description = "Extra GCP labels for the instance and its boot disk. Keys and values must already be valid GCP labels; the captf-io_ keys are reserved for captf_tags, which win."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = length(var.additional_tags) <= 58
    error_message = "additional_tags holds at most 58 labels: GCP allows 64 per resource and captf_tags takes 6."
  }
  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "additional_tags keys must match ^[a-z][a-z0-9_-]{0,62}$ and values ^[a-z0-9_-]{0,63}$ (GCP label syntax)."
  }
  validation {
    condition     = alltrue([for k in keys(var.additional_tags) : !startswith(k, "captf-io_")])
    error_message = "additional_tags must not use keys starting with captf-io_: they are reserved for the mapped captf_tags."
  }
}

variable "boot_disk_kms_key_id" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) that encrypts the boot disk. Null uses Google-managed encryption; the Compute Engine service agent needs encrypt and decrypt on the key."
  type        = string
  default     = null

  validation {
    condition     = var.boot_disk_kms_key_id == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.boot_disk_kms_key_id))
    error_message = "boot_disk_kms_key_id must be a key name such as projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>."
  }
}

variable "boot_disk_size_gib" {
  description = "Boot disk size in GiB: room for the image, container images and logs."
  type        = number
  default     = 50
  nullable    = false

  validation {
    condition     = var.boot_disk_size_gib >= 10 && floor(var.boot_disk_size_gib) == var.boot_disk_size_gib
    error_message = "boot_disk_size_gib must be a whole number of at least 10."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type. pd-balanced suits the default N2 machine type; C3, N4 and newer series need hyperdisk-balanced."
  type        = string
  default     = "pd-balanced"
  nullable    = false

  validation {
    condition     = can(regex("^(pd|hyperdisk)-[a-z-]+$", var.boot_disk_type))
    error_message = "boot_disk_type must be a Persistent Disk or Hyperdisk type such as pd-balanced or hyperdisk-balanced."
  }
}

variable "bootstrap_delivery" {
  description = "How a control-plane machine's cloud-config payload reaches it. secret-manager (default) stages it in a per-machine secret behind a small user-data stub, which needs curl, sed, base64 and gzip in the image; inline puts it in instance metadata, where compute.instances.get and the metadata server expose the cluster's CA keys. Workers and Ignition are always inline."
  type        = string
  default     = "secret-manager"
  nullable    = false

  validation {
    condition     = contains(["secret-manager", "inline"], var.bootstrap_delivery)
    error_message = "bootstrap_delivery must be secret-manager or inline."
  }
}

variable "can_ip_forward" {
  description = "Let the instance send and receive packets for other addresses, as CNIs that route pod CIDRs through GCP routes need. Off by default."
  type        = bool
  default     = false
  nullable    = false
}

variable "external_cluster_exports" {
  description = "Exports (schema captf.io/gcp-cluster/v1) to use when the TerraformCluster is externally managed and captf_cluster_outputs is {}. Ignored otherwise."
  type        = any
  default     = null

  validation {
    condition     = var.external_cluster_exports == null || try(var.external_cluster_exports.schema == "captf.io/gcp-cluster/v1", false)
    error_message = "external_cluster_exports must be an object with schema = \"captf.io/gcp-cluster/v1\" and the keys the gcp-cluster module exports."
  }
}

variable "image" {
  description = "Boot image: a name, family/<family>, projects/<p>/global/images/<image> or a self link. {version}, {semver}, {slug} and {fullslug} are replaced by v1.33.4, 1.33.4, v1-33-4 and v1-33-4-rke2r1 (suffix kept) from kubernetes_version. Required."
  type        = string
  default     = null

  validation {
    condition     = var.image != null
    error_message = "image is required: set spec.template.spec.variables.image on the TerraformMachineTemplate to a Kubernetes node image, for example one built with image-builder."
  }
  validation {
    condition     = var.image == null || can(regex("^\\S+$", var.image))
    error_message = "image must not contain whitespace."
  }
}

variable "machine_type" {
  description = "Machine type of the instance. The default matches the image's io.captf.capacity label (4 vCPU, 16 GiB)."
  type        = string
  default     = "n2-standard-4"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]+-[a-z0-9-]+$", var.machine_type))
    error_message = "machine_type must be a machine type name such as n2-standard-4."
  }
}

variable "secure_boot" {
  description = "Shielded VM Secure Boot. On by default; turn it off only for images whose kernel modules are unsigned (some GPU drivers)."
  type        = bool
  default     = true
  nullable    = false
}

variable "spot" {
  description = "Run as a Spot VM: cheaper, preemptible at any time; a preempted instance stops and reports stopped. Off by default."
  type        = bool
  default     = false
  nullable    = false
}
