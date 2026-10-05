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

# Non-contract outputs: ids of what the module created, for operators and for
# the tests' stability checks. The controller never reads them. Alphabetical.

output "api_instance_group_membership_id" {
  description = "ID of the API instance group membership; null for workers and user endpoints."
  value       = try(google_compute_instance_group_membership.api_instance_group_membership[0].id, null)
}

output "instance_id" {
  description = "Unique numeric ID of the instance; changes only when the instance is replaced."
  value       = one(google_compute_instance.node_instance[*].instance_id)
}

output "instance_self_link" {
  description = "Self link of the instance."
  value       = one(google_compute_instance.node_instance[*].self_link)
}
