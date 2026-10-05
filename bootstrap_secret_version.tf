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

# The staged payload itself. is_secret_data_base64 takes bootstrap_data as it
# is and Secret Manager stores the decoded bytes, so a gzip payload arrives
# intact for the stub to decompress.
resource "google_secret_manager_secret_version" "bootstrap_secret_version" {
  count = local.bootstrap_staged ? 1 : 0

  is_secret_data_base64 = true
  secret                = google_secret_manager_secret.bootstrap_secret[0].id
  secret_data           = var.bootstrap_data
}
