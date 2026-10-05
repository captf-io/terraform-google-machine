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

# captf_tags as GCP labels (CONVENTIONS.md section 7; README "Tags"). Keys match
# [a-z][a-z0-9_-]{0,62} and values [a-z0-9_-]{0,63}, so "captf.io/cluster" is not
# a valid key (https://cloud.google.com/compute/docs/labeling-resources).
locals {
  # Values: lowercase, invalid characters to "_".
  captf_label_values = { for k, v in var.captf_tags : k => replace(lower(v), "/[^a-z0-9_-]/", "_") }

  # Keys: lowercase, "." to "-", other invalid characters to "_"
  # (captf.io/cluster -> captf-io_cluster). Values longer than 63 characters
  # keep 54 and append "-" and 8 hex characters of the original's sha256, so
  # two long values never collide.
  captf_tags = {
    for k, v in local.captf_label_values :
    replace(replace(lower(k), ".", "-"), "/[^a-z0-9_-]/", "_") => (
      length(v) <= 63 ? v : "${substr(v, 0, 54)}-${substr(sha256(var.captf_tags[k]), 0, 8)}"
    )
  }

  # cloud-provider-gcp needs no labels on nodes or load balancers.
  cloud_tags = {}

  # captf keys merge last, so additional_tags cannot override them.
  tags = merge(var.additional_tags, local.cloud_tags, local.captf_tags)
}
