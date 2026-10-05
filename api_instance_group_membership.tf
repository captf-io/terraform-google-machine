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

# A control-plane instance joins its zone's API instance group in this
# machine's own state, so destroying the machine deregisters it
# (machine.md "Control-plane machines"; DESIGN.md decision 4).
resource "google_compute_instance_group_membership" "api_instance_group_membership" {
  count = var.control_plane && local.api_instance_groups != null ? 1 : 0

  instance       = google_compute_instance.node_instance[0].self_link
  instance_group = local.api_instance_group_parts.name
  project        = local.api_instance_group_parts.project
  zone           = local.api_instance_group_parts.zone

  lifecycle {
    # A replaced instance keeps its self link but leaves the group; its new
    # instance_id re-creates the membership, as the provider docs advise.
    replace_triggered_by = [google_compute_instance.node_instance[0].instance_id]
  }
}
