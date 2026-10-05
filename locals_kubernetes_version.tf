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

# kubernetes_version in the forms image names use. The +rke2rN suffix is
# build metadata: stripped by most placeholders, kept by {fullslug}
# (machine.md "kubernetes_version").
locals {
  kubernetes_semver = var.kubernetes_version == null ? null : trimprefix(split("+", var.kubernetes_version)[0], "v")
  # The whole version, suffix included, as a name: v1.31.4+rke2r2 is
  # v1-31-4-rke2r2 (image names allow only [a-z0-9-]).
  kubernetes_fullslug   = var.kubernetes_version == null ? null : "v${replace(lower(trimprefix(var.kubernetes_version, "v")), "/[^a-z0-9]/", "-")}"
  image_placeholders    = ["{version}", "{semver}", "{slug}", "{fullslug}"]
  image_has_placeholder = var.image == null ? false : anytrue([for p in local.image_placeholders : strcontains(var.image, p)])

  # Image placeholders: {version} v1.33.4, {semver} 1.33.4, {slug} v1-33-4,
  # {fullslug} v1-31-4-rke2r2 (all of the version, for RKE2 builds).
  image = (
    var.image == null || local.kubernetes_semver == null ? var.image :
    replace(replace(replace(replace(var.image,
      "{version}", "v${local.kubernetes_semver}"),
      "{semver}", local.kubernetes_semver),
      "{slug}", "v${replace(local.kubernetes_semver, ".", "-")}"),
    "{fullslug}", local.kubernetes_fullslug)
  )
}
