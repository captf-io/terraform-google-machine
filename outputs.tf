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

# Contract outputs of the machine role, in contract order:
# https://captf.io/docs/module-author/contract/v1alpha1/machine.html#outputs
# and "health" in https://captf.io/docs/module-author/contract/v1alpha1/common.html

output "provider_id" {
  description = "gce://<project>/<zone>/<instance>, what cloud-provider-gcp writes to Node.spec.providerID (README \"Outputs\")."
  value       = one([for i in google_compute_instance.node_instance : "gce://${i.project}/${i.zone}/${i.name}"])
}

# cloud-provider-gcp reports the NICs' InternalIP and any ExternalIP, nothing
# else (nodeAddressesFromInstance in providers/gce/gce_instances.go, v37.1.1).
output "addresses" {
  description = "InternalIP and any ExternalIP of the instance, as cloud-provider-gcp reports them (machine.md \"addresses\")."
  value = flatten([
    for i in google_compute_instance.node_instance : [
      for nic in i.network_interface : concat(
        nic.network_ip == null || nic.network_ip == "" ? [] : [{ type = "InternalIP", address = nic.network_ip }],
        [for ac in nic.access_config : { type = "ExternalIP", address = ac.nat_ip } if ac.nat_ip != null && ac.nat_ip != ""],
      )
    ]
  ])
}

output "failure_domain" {
  description = "The instance's zone: the requested failure domain, or the one the module picked (machine.md \"failure_domain\")."
  value       = try(coalesce(one(google_compute_instance.node_instance[*].zone), local.zone), null)
}

output "interruptible" {
  description = "True for a Spot VM (machine.md \"interruptible\")."
  value       = one(google_compute_instance.node_instance[*].scheduling[0].provisioning_model) == "SPOT"
}

output "health" {
  description = "Health from the instance status (README \"Health\"; common.md \"health\")."
  value       = local.health_reading
}
