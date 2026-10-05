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

# Machine health from the instance status, re-read on every refresh
# (CONVENTIONS.md section 10; "health" in common.md). States:
# https://cloud.google.com/compute/docs/instances/instance-lifecycle
locals {
  # Compute Engine instance status -> contract health. Every status of the
  # v1 API's Instance.status enum is listed.
  health_by_state = {
    RUNNING      = { state = "running", healthy = true, reason = null }
    PENDING      = { state = "pending", healthy = false, reason = "InstancePending" }
    PROVISIONING = { state = "pending", healthy = false, reason = "InstanceProvisioning" }
    STAGING      = { state = "pending", healthy = false, reason = "InstanceStaging" }
    REPAIRING    = { state = "degraded", healthy = false, reason = "InstanceRepairing" }
    PENDING_STOP = { state = "stopped", healthy = false, reason = "InstancePendingStop" }
    STOPPING     = { state = "stopped", healthy = false, reason = "InstanceStopping" }
    STOPPED      = { state = "stopped", healthy = false, reason = "InstanceStopped" }
    SUSPENDING   = { state = "stopped", healthy = false, reason = "InstanceSuspending" }
    SUSPENDED    = { state = "stopped", healthy = false, reason = "InstanceSuspended" }
    # TERMINATED is Compute Engine's word for stopped: the instance and its
    # disk still exist, and a start brings it back.
    TERMINATED = { state = "stopped", healthy = false, reason = "InstanceTerminated" }
    # The API documents DEPROVISIONING as tearing down the instance's network,
    # IP and disks: the instance is going away (DESIGN.md "Unverified").
    DEPROVISIONING = { state = "terminated", healthy = false, reason = "InstanceNotFound" }
  }

  # Null once a refresh no longer finds the instance. Splats, not one() of
  # the whole object: its metadata is sensitive and would mark everything.
  instance_status = one(google_compute_instance.node_instance[*].current_status)
  health_mapped   = local.instance_status == null ? null : lookup(local.health_by_state, upper(local.instance_status), { state = "unknown", healthy = false, reason = "UnknownState" })

  health_reading = local.health_mapped == null ? {
    state   = "terminated"
    healthy = false
    message = "Instance ${local.instance_name} no longer exists."
    reasons = ["InstanceNotFound"]
    } : {
    state   = local.health_mapped.state
    healthy = local.health_mapped.healthy
    message = "Instance ${local.instance_name} is ${local.instance_status}."
    reasons = local.health_mapped.reason == null ? [] : [local.health_mapped.reason]
  }
}
