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

# The zone the instance runs in: the requested failure domain, or a
# deterministic pick from the cluster's zones (CONVENTIONS.md section 11).
locals {
  # sha256(machine_name) over the sorted zones: stable across runs, spread
  # across zones for many machines.
  defaulted_zone = length(local.failure_domains) == 0 ? null : local.failure_domains[parseint(substr(sha256(var.machine_name), 0, 8), 16) % length(local.failure_domains)]
  zone           = var.failure_domain != null ? var.failure_domain : local.defaulted_zone

  # The API instance group of the instance's zone, as project, zone and name:
  # the membership API takes the group's name, not its URL.
  api_instance_group_parts = try(regex("projects/(?P<project>[^/]+)/zones/(?P<zone>[^/]+)/instanceGroups/(?P<name>[^/]+)$", local.api_instance_groups[local.zone]), null)
}
