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

# Contract inputs of the machine role, in contract order, with the contract's
# types: https://captf.io/docs/module-author/contract/v1alpha1/common.html and
# https://captf.io/docs/module-author/contract/v1alpha1/machine.html

# Read only by its own validation.
# tflint-ignore: terraform_unused_declarations
variable "captf_contract" {
  description = "Contract version the controller generated the root module for."
  type        = string

  validation {
    condition     = var.captf_contract == "v1alpha1"
    error_message = "captf_contract must be \"v1alpha1\": this module implements the v1alpha1 machine role only."
  }
}

variable "captf_cluster" {
  description = "The owning CAPI Cluster."
  type = object({
    name      = string
    namespace = string
  })
}

variable "captf_object" {
  description = "The TerraformMachine being reconciled."
  type = object({
    kind      = string
    name      = string
    namespace = string
  })
}

variable "captf_cluster_outputs" {
  description = "The cluster role's exports (schema captf.io/gcp-cluster/v1), or {} for an externally managed TerraformCluster."
  type        = any

  validation {
    condition     = try(length(var.captf_cluster_outputs) == 0, false) || try(var.captf_cluster_outputs.schema == "captf.io/gcp-cluster/v1", false)
    error_message = "captf_cluster_outputs must be exports of schema captf.io/gcp-cluster/v1 (from the gcp-cluster module) or {}: the TerraformCluster runs a different cluster module."
  }
}

variable "captf_tags" {
  description = "Fixed captf.io/* tags the controller sets; applied as GCP labels to the instance and its boot disk."
  type        = map(string)
}

variable "machine_name" {
  description = "Name of the owning CAPI Machine; the instance and Node name, made valid for Compute Engine."
  type        = string
}

variable "bootstrap_data" {
  description = "Base64 of the bootstrap Secret's value: cloud-config or Ignition, possibly gzipped."
  type        = string
  sensitive   = true
}

variable "bootstrap_format" {
  description = "Format of the decoded bootstrap payload: cloud-config or ignition."
  type        = string

  validation {
    condition     = contains(["cloud-config", "ignition"], var.bootstrap_format)
    error_message = "bootstrap_format must be cloud-config or ignition."
  }
}

variable "failure_domain" {
  description = "Machine.spec.failureDomain: the zone to place the instance in, or null to let the module pick one."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Machine.spec.version, possibly with a +rke2rN suffix; substituted into image placeholders."
  type        = string
  default     = null
}

variable "control_plane" {
  description = "True for control-plane Machines: the instance joins the API load balancer."
  type        = bool
}
