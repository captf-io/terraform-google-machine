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

# The Google provider, in the cluster's project and region from exports.
# Credentials come only from the identity Secret; with no exports yet the
# provider falls back to GOOGLE_PROJECT and GOOGLE_REGION.
provider "google" {
  # Every label is set explicitly from local.tags (CONVENTIONS.md section 7).
  add_terraform_attribution_label = false
  project                         = local.project
  region                          = local.region
}
