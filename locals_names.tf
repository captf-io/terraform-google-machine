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

# The instance name is the Node name: cloud-provider-gcp looks instances up by
# Node name, so it is machine_name made valid for Compute Engine
# (CONVENTIONS.md section 6; README "Limitations").
locals {
  # Names are [a-z]([-a-z0-9]{0,61}[a-z0-9])?
  # (https://cloud.google.com/compute/docs/naming-resources).
  machine_name_valid = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.machine_name))
  # Otherwise: invalid characters to "-", a leading letter, at most 54
  # characters, then "-" and 8 hex characters of machine_name's sha256.
  machine_slug  = replace(lower(var.machine_name), "/[^a-z0-9-]/", "-")
  machine_base  = can(regex("^[a-z]", local.machine_slug)) ? local.machine_slug : "m-${local.machine_slug}"
  instance_name = local.machine_name_valid ? var.machine_name : "${trimsuffix(substr(local.machine_base, 0, 54), "-")}-${substr(sha256(var.machine_name), 0, 8)}"

  # Not labelable resources and descriptions name the objects, never
  # captf_tags.
  description = "CAPTF machine ${var.captf_object.namespace}/${var.machine_name} of cluster ${var.captf_cluster.namespace}/${var.captf_cluster.name}"
}
