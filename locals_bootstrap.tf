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

# What the instance boots with (CONVENTIONS.md section 13; DESIGN.md
# decision 4). bootstrap_data is base64 of the payload; gzip starts with the
# bytes 1f 8b, whose base64 is "H4sI".
locals {
  # Whether the payload is compressed is not secret.
  bootstrap_gzipped = nonsensitive(startswith(var.bootstrap_data, "H4sI"))

  # Control-plane payloads hold the cluster's CA and service-account keys:
  # staged in Secret Manager behind a stub, never in readable instance
  # metadata (control-planes/checklist.md "CP bootstrap payload size and
  # secrecy"). Ignition cannot run the stub's fetch, and worker payloads hold
  # only a short-lived join token, so both go inline.
  bootstrap_staged = var.control_plane && var.bootstrap_format == "cloud-config" && var.bootstrap_delivery == "secret-manager"

  # The stub: a boothook that fetches the payload and writes it as system
  # config to cloud.cfg.d, which cloud-init re-reads after consuming
  # user-data and before its config stages. Not an x-include-url part: stock
  # cloud-init resolves includes before boothooks run, so the file would not
  # exist yet and init aborts.
  bootstrap_stub = templatefile("${path.module}/templates/bootstrap_fetch.tftpl", {
    secret_version = try(google_secret_manager_secret_version.bootstrap_secret_version[0].name, "-")
  })

  # cloud-config, plain or gzipped: sent as base64 with
  # user-data-encoding=base64, which cloud-init's GCE datasource decodes
  # before it decompresses a gzip payload (cloudinit/sources/DataSourceGCE.py).
  # Ignition reads user-data raw, so it is decoded here, and only when it is
  # not gzipped; a gzipped Ignition payload fails the instance's precondition.
  user_data = (
    local.bootstrap_staged ? base64encode(local.bootstrap_stub) :
    var.bootstrap_format == "cloud-config" ? var.bootstrap_data :
    # Safe outside a cloud-config check (CONVENTIONS.md section 13): an
    # Ignition config is JSON, so UTF-8, once gzip is ruled out.
    var.bootstrap_format == "ignition" && !local.bootstrap_gzipped ? base64decode(var.bootstrap_data) :
    ""
  )
  user_data_metadata = var.bootstrap_format == "cloud-config" ? tomap({
    "user-data"          = local.user_data
    "user-data-encoding" = "base64"
    }) : tomap({
    "user-data" = local.user_data
  })

  # A metadata value holds at most 256 KB
  # (https://cloud.google.com/compute/docs/metadata/setting-custom-metadata#limitations),
  # a secret version 64 KiB (https://cloud.google.com/secret-manager/quotas).
  user_data_max_bytes = 262144
  # Decoded size of the staged payload.
  bootstrap_bytes  = floor(length(var.bootstrap_data) / 4) * 3 - (endswith(var.bootstrap_data, "==") ? 2 : endswith(var.bootstrap_data, "=") ? 1 : 0)
  secret_max_bytes = 65536
}
