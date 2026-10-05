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

# What the machine takes from the cluster: the exports of the gcp-cluster
# module, or external_cluster_exports when the TerraformCluster is externally
# managed and the controller passes {} (CONVENTIONS.md section 12).
locals {
  externally_managed = try(length(var.captf_cluster_outputs) == 0, false)
  # A tuple index, not a conditional: the two objects have different types,
  # which a conditional's result types must not.
  cluster_exports = [var.captf_cluster_outputs, var.external_cluster_exports][local.externally_managed ? 1 : 0]

  # try(): every value is null until exports exist, so the instance's
  # precondition reports the missing exports instead of an attribute error.
  project         = try(local.cluster_exports.project, null)
  region          = try(local.cluster_exports.region, null)
  subnetwork      = try(local.cluster_exports.subnetwork, null)
  failure_domains = try(sort(keys(local.cluster_exports.failure_domains)), [])
  node_role       = var.control_plane ? "control_plane" : "worker"
  service_account = try(local.cluster_exports[local.node_role].service_account, null)
  network_tags    = distinct(concat(try(local.cluster_exports[local.node_role].network_tags, []), var.additional_network_tags))
  # The API instance groups to join; null for a user endpoint.
  api_instance_groups = try(local.cluster_exports.api.instance_groups, null)
}
