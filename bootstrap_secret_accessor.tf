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

# Only the control-plane node service account may read the staged payload,
# and only this one secret: a resource-level binding in the machine's own
# state, gone with the machine.
resource "google_secret_manager_secret_iam_member" "bootstrap_secret_accessor" {
  count = local.bootstrap_staged ? 1 : 0

  member    = "serviceAccount:${local.service_account}"
  project   = local.project
  role      = "roles/secretmanager.secretAccessor"
  secret_id = google_secret_manager_secret.bootstrap_secret[0].id
}
