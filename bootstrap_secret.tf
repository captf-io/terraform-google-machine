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

# The secret a control-plane machine's bootstrap payload is staged in, so its
# keys stay out of instance metadata (locals_bootstrap.tf). Replicated in the
# cluster's region only; destroying the machine deletes it.
resource "google_secret_manager_secret" "bootstrap_secret" {
  count = local.bootstrap_staged ? 1 : 0

  labels    = local.tags
  project   = local.project
  secret_id = "${local.instance_name}-${coalesce(local.zone, "-")}-bootstrap"

  replication {
    user_managed {
      replicas {
        location = local.region
      }
    }
  }
}
