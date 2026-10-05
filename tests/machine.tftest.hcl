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

# Unit tests of the machine role with a mocked Google provider: nothing
# reaches GCP. Run from the role directory with `terraform test` or
# `tofu test`, or `make unit-test`. Run names follow CONVENTIONS.md
# section 14.

mock_provider "google" {
  mock_resource "google_compute_instance" {
    defaults = {
      current_status = "RUNNING"
      self_link      = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instances/demo-md-0-x7k2p-9zq4r"
    }
  }

  mock_resource "google_secret_manager_secret" {
    defaults = {
      id   = "projects/captf-test/secrets/demo-control-plane-x7k2p-us-central1-b-bootstrap"
      name = "projects/123456789012/secrets/demo-control-plane-x7k2p-us-central1-b-bootstrap"
    }
  }

  mock_resource "google_secret_manager_secret_version" {
    defaults = {
      name    = "projects/123456789012/secrets/demo-control-plane-x7k2p-us-central1-b-bootstrap/versions/1"
      version = "1"
    }
  }
}

variables {
  captf_contract = "v1alpha1"
  captf_cluster  = { name = "demo", namespace = "team-a" }
  captf_object   = { kind = "TerraformMachine", name = "demo-md-0-x7k2p-9zq4r", namespace = "team-a" }
  captf_tags = {
    "captf.io/cluster"    = "demo"
    "captf.io/namespace"  = "team-a"
    "captf.io/kind"       = "TerraformMachine"
    "captf.io/name"       = "demo-md-0-x7k2p-9zq4r"
    "captf.io/managed-by" = "captf"
    "captf.io/template"   = "demo-md-0"
  }
  captf_cluster_outputs = {
    schema      = "captf.io/gcp-cluster/v1"
    project     = "captf-test"
    region      = "us-central1"
    network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
    subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
    name_prefix = "captf-team-a-demo-1d4e2f6a"
    failure_domains = {
      "us-central1-a" = { zone = "us-central1-a" }
      "us-central1-b" = { zone = "us-central1-b" }
      "us-central1-c" = { zone = "us-central1-c" }
      "us-central1-f" = { zone = "us-central1-f" }
    }
    node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
    control_plane = {
      service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
      network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
    }
    worker = {
      service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
      network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
    }
    api = {
      host         = "10.0.0.10"
      port         = 6443
      backend_port = 6443
      instance_groups = {
        "us-central1-a" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-b" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-c" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        "us-central1-f" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-f/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
      }
    }
  }
  machine_name = "demo-md-0-x7k2p-9zq4r"
  # base64 of "## template: jinja\n#cloud-config\nruncmd: [kubeadm join]\n"
  bootstrap_data     = "IyMgdGVtcGxhdGU6IGppbmphCiNjbG91ZC1jb25maWcKcnVuY21kOiBba3ViZWFkbSBqb2luXQo="
  bootstrap_format   = "cloud-config"
  failure_domain     = "us-central1-b"
  kubernetes_version = "v1.33.4"
  control_plane      = false

  image = "projects/captf-images/global/images/capi-ubuntu-2404-{slug}"
}

run "happy_path" {
  assert {
    condition     = output.provider_id == "gce://captf-test/us-central1-b/demo-md-0-x7k2p-9zq4r"
    error_message = "provider_id must be gce://<project>/<zone>/<instance name>, as cloud-provider-gcp writes it."
  }
  assert {
    condition     = length(google_secret_manager_secret.bootstrap_secret) == 0
    error_message = "A worker's payload (a join token) goes inline: nothing is staged."
  }
  assert {
    condition     = length([for a in output.addresses : a if a.type == "InternalIP"]) == 1 && length([for a in output.addresses : a if a.type == "ExternalIP"]) == 0
    error_message = "A node has one InternalIP and no ExternalIP."
  }
  assert {
    condition     = length(output.addresses) == 1 && output.addresses[0].address == google_compute_instance.node_instance[0].network_interface[0].network_ip
    error_message = "addresses mirror cloud-provider-gcp: the NIC's InternalIP only, without an external IP."
  }
  assert {
    condition     = output.failure_domain == "us-central1-b"
    error_message = "failure_domain must equal the requested zone."
  }
  assert {
    condition     = output.interruptible == false
    error_message = "A standard VM is not interruptible."
  }
  assert {
    condition     = output.health.state == "running" && output.health.healthy && length(output.health.reasons) == 0
    error_message = "A RUNNING instance is running and healthy."
  }
  assert {
    condition     = output.health.message == "Instance demo-md-0-x7k2p-9zq4r is RUNNING."
    error_message = "health.message must name the instance status."
  }
  assert {
    condition     = output.api_instance_group_membership_id == null && output.instance_id != null
    error_message = "A worker has an instance and no membership."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].image == "projects/captf-images/global/images/capi-ubuntu-2404-v1-33-4"
    error_message = "{slug} must become v1-33-4."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].machine_type == "n2-standard-4" && google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].type == "pd-balanced" && google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].size == 50
    error_message = "Defaults: n2-standard-4, 50 GiB pd-balanced."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].service_account[0].email == "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
    error_message = "A worker runs as the worker service account."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].tags == toset(["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"])
    error_message = "A worker carries the node and worker network tags."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].network_interface[0].subnetwork == "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes" && length(google_compute_instance.node_instance[0].network_interface[0].access_config) == 0
    error_message = "The instance joins the cluster's subnetwork with no external IP."
  }
  assert {
    condition = alltrue([
      google_compute_instance.node_instance[0].shielded_instance_config[0].enable_secure_boot,
      google_compute_instance.node_instance[0].shielded_instance_config[0].enable_vtpm,
      google_compute_instance.node_instance[0].shielded_instance_config[0].enable_integrity_monitoring,
    ])
    error_message = "Shielded VM is fully on by default."
  }
  assert {
    condition = alltrue([
      google_compute_instance.node_instance[0].metadata["block-project-ssh-keys"] == "TRUE",
      google_compute_instance.node_instance[0].metadata["enable-oslogin"] == "TRUE",
      google_compute_instance.node_instance[0].metadata["serial-port-enable"] == "FALSE",
    ])
    error_message = "OS Login on, project SSH keys blocked, serial port off."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].project == "captf-test" && google_compute_instance.node_instance[0].zone == "us-central1-b"
    error_message = "The instance is created in the cluster's project and the requested zone."
  }
}

run "reapply_is_stable" {
  variables {
    previous_instance_id = run.happy_path.instance_id
    previous_provider_id = run.happy_path.provider_id
  }

  assert {
    condition     = output.instance_id == var.previous_instance_id && output.provider_id == var.previous_provider_id
    error_message = "A second apply must keep the instance."
  }
}

run "tags_on_taggable_resources" {
  variables {
    additional_tags = { team = "platform" }
  }

  assert {
    condition = google_compute_instance.node_instance[0].labels == tomap({
      "captf-io_cluster"    = "demo"
      "captf-io_namespace"  = "team-a"
      "captf-io_kind"       = "terraformmachine"
      "captf-io_name"       = "demo-md-0-x7k2p-9zq4r"
      "captf-io_managed-by" = "captf"
      "captf-io_template"   = "demo-md-0"
      "team"                = "platform"
    })
    error_message = "The instance must carry the mapped captf_tags and additional_tags."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].labels == google_compute_instance.node_instance[0].labels
    error_message = "The boot disk must carry the same labels."
  }
}

run "control_plane_registers_backend" {
  variables {
    control_plane = true
  }

  assert {
    condition     = length(google_compute_instance_group_membership.api_instance_group_membership) == 1
    error_message = "A control-plane machine joins the API instance group."
  }
  assert {
    condition = alltrue([
      google_compute_instance_group_membership.api_instance_group_membership[0].instance_group == "captf-team-a-demo-1d4e2f6a-control-plane",
      google_compute_instance_group_membership.api_instance_group_membership[0].zone == "us-central1-b",
      google_compute_instance_group_membership.api_instance_group_membership[0].project == "captf-test",
    ])
    error_message = "The membership targets the instance group of the instance's zone."
  }
  assert {
    condition     = google_compute_instance_group_membership.api_instance_group_membership[0].instance == google_compute_instance.node_instance[0].self_link
    error_message = "The membership registers this instance."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].service_account[0].email == "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
    error_message = "A control-plane machine runs as the control-plane service account."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].tags == toset(["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"])
    error_message = "A control-plane machine carries the node and control-plane network tags."
  }
}

run "control_plane_bootstrap_staged" {
  variables {
    control_plane = true
  }

  assert {
    condition     = google_secret_manager_secret_version.bootstrap_secret_version[0].is_secret_data_base64 && nonsensitive(google_secret_manager_secret_version.bootstrap_secret_version[0].secret_data) == var.bootstrap_data
    error_message = "The control-plane payload is staged in the secret version, as it is."
  }
  assert {
    condition     = !strcontains(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), var.bootstrap_data) && !strcontains(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), "kubeadm")
    error_message = "Instance metadata holds only the stub, never the payload."
  }
  assert {
    condition     = strcontains(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), "https://secretmanager.googleapis.com/v1/projects/123456789012/secrets/demo-control-plane-x7k2p-us-central1-b-bootstrap/versions/1:access") && strcontains(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), "config=/etc/cloud/cloud.cfg.d/99-captf-bootstrap.cfg") && startswith(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), "#cloud-boothook\n") && !strcontains(nonsensitive(base64decode(google_compute_instance.node_instance[0].metadata["user-data"])), "x-include-url")
    error_message = "The stub fetches this machine's secret version into cloud.cfg.d, with no include part."
  }
  assert {
    condition = alltrue([
      google_secret_manager_secret_iam_member.bootstrap_secret_accessor[0].role == "roles/secretmanager.secretAccessor",
      google_secret_manager_secret_iam_member.bootstrap_secret_accessor[0].member == "serviceAccount:captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com",
      google_secret_manager_secret_iam_member.bootstrap_secret_accessor[0].secret_id == google_secret_manager_secret.bootstrap_secret[0].id,
    ])
    error_message = "Only the control-plane service account may read the secret, and only this one."
  }
  assert {
    condition     = google_secret_manager_secret.bootstrap_secret[0].replication[0].user_managed[0].replicas[0].location == "us-central1" && google_secret_manager_secret.bootstrap_secret[0].labels["captf-io_cluster"] == "demo"
    error_message = "The secret is replicated in the cluster's region and labelled."
  }
}

run "control_plane_bootstrap_inline" {
  variables {
    control_plane      = true
    bootstrap_delivery = "inline"
  }

  assert {
    condition     = length(google_secret_manager_secret.bootstrap_secret) == 0 && nonsensitive(google_compute_instance.node_instance[0].metadata["user-data"]) == var.bootstrap_data
    error_message = "bootstrap_delivery = inline puts the payload in metadata and stages nothing."
  }
}

run "control_plane_ignition_inline" {
  command = plan

  variables {
    control_plane    = true
    bootstrap_format = "ignition"
    bootstrap_data   = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
  }

  assert {
    condition     = length(google_secret_manager_secret.bootstrap_secret) == 0
    error_message = "Ignition cannot run the stub, so its payload goes inline (README \"Exceptions\")."
  }
}

run "rejects_staged_payload_too_large" {
  command = plan

  variables {
    control_plane = true
    # 90000 base64 characters: about 67500 bytes, over the 65536 of a secret.
    bootstrap_data = format("%090000d", 0)
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "worker_has_no_backend" {
  variables {
    control_plane = false
  }

  assert {
    condition     = length(google_compute_instance_group_membership.api_instance_group_membership) == 0
    error_message = "A worker never joins the API instance group."
  }
}

run "control_plane_user_endpoint_has_no_backend" {
  variables {
    control_plane = true
    captf_cluster_outputs = {
      schema      = "captf.io/gcp-cluster/v1"
      project     = "captf-test"
      region      = "us-central1"
      network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      name_prefix = "captf-team-a-demo-1d4e2f6a"
      failure_domains = {
        "us-central1-a" = { zone = "us-central1-a" }
        "us-central1-b" = { zone = "us-central1-b" }
        "us-central1-c" = { zone = "us-central1-c" }
        "us-central1-f" = { zone = "us-central1-f" }
      }
      node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
      control_plane = {
        service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
      }
      worker = {
        service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
      }
      api = null
    }
  }

  assert {
    condition     = length(google_compute_instance_group_membership.api_instance_group_membership) == 0
    error_message = "With a user endpoint there is no instance group to join."
  }
}

run "failure_domain_requested" {
  variables {
    failure_domain = "us-central1-f"
  }

  assert {
    condition     = output.failure_domain == "us-central1-f" && google_compute_instance.node_instance[0].zone == "us-central1-f"
    error_message = "The instance must be placed in the requested failure domain."
  }
}

run "failure_domain_defaulted" {
  variables {
    failure_domain = null
  }

  assert {
    condition     = output.failure_domain == ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"][parseint(substr(sha256("demo-md-0-x7k2p-9zq4r"), 0, 8), 16) % 4]
    error_message = "Without a failure domain the zone is sha256(machine_name) over the sorted zones."
  }
}

run "unknown_failure_domain" {
  command = plan

  variables {
    failure_domain = "us-east1-b"
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "spot_is_interruptible" {
  variables {
    spot = true
  }

  assert {
    condition     = output.interruptible == true
    error_message = "A Spot VM is interruptible."
  }
  assert {
    condition = alltrue([
      google_compute_instance.node_instance[0].scheduling[0].provisioning_model == "SPOT",
      google_compute_instance.node_instance[0].scheduling[0].preemptible,
      !google_compute_instance.node_instance[0].scheduling[0].automatic_restart,
      google_compute_instance.node_instance[0].scheduling[0].instance_termination_action == "STOP",
    ])
    error_message = "A Spot VM stops when preempted."
  }
}

run "rejects_spot_control_plane" {
  command = plan

  variables {
    control_plane = true
    spot          = true
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "externally_managed_without_override" {
  command = plan

  variables {
    captf_cluster_outputs = {}
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "externally_managed_with_override" {
  variables {
    external_cluster_exports = {
      schema      = "captf.io/gcp-cluster/v1"
      project     = "captf-test"
      region      = "us-central1"
      network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      name_prefix = "captf-team-a-demo-1d4e2f6a"
      failure_domains = {
        "us-central1-a" = { zone = "us-central1-a" }
        "us-central1-b" = { zone = "us-central1-b" }
        "us-central1-c" = { zone = "us-central1-c" }
        "us-central1-f" = { zone = "us-central1-f" }
      }
      node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
      control_plane = {
        service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
      }
      worker = {
        service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
      }
      api = {
        host         = "10.0.0.10"
        port         = 6443
        backend_port = 6443
        instance_groups = {
          "us-central1-a" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-b" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-c" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-f" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-f/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        }
      }
    }
    captf_cluster_outputs = {}
  }

  assert {
    condition     = output.provider_id == "gce://captf-test/us-central1-b/demo-md-0-x7k2p-9zq4r"
    error_message = "external_cluster_exports stands in for the cluster's exports."
  }
}

run "wrong_exports_schema" {
  command = plan

  variables {
    captf_cluster_outputs = {
      schema      = "captf.io/aws-cluster/v1"
      project     = "captf-test"
      region      = "us-central1"
      network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      name_prefix = "captf-team-a-demo-1d4e2f6a"
      failure_domains = {
        "us-central1-a" = { zone = "us-central1-a" }
        "us-central1-b" = { zone = "us-central1-b" }
        "us-central1-c" = { zone = "us-central1-c" }
        "us-central1-f" = { zone = "us-central1-f" }
      }
      node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
      control_plane = {
        service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
      }
      worker = {
        service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
      }
      api = {
        host         = "10.0.0.10"
        port         = 6443
        backend_port = 6443
        instance_groups = {
          "us-central1-a" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-a/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-b" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-b/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-c" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-c/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
          "us-central1-f" = "https://www.googleapis.com/compute/v1/projects/captf-test/zones/us-central1-f/instanceGroups/captf-team-a-demo-1d4e2f6a-control-plane"
        }
      }
    }
  }

  expect_failures = [var.captf_cluster_outputs]
}

run "bootstrap_cloud_config" {
  assert {
    condition     = nonsensitive(google_compute_instance.node_instance[0].metadata["user-data"]) == "IyMgdGVtcGxhdGU6IGppbmphCiNjbG91ZC1jb25maWcKcnVuY21kOiBba3ViZWFkbSBqb2luXQo="
    error_message = "cloud-config is passed unchanged, as base64."
  }
  assert {
    condition     = google_compute_instance.node_instance[0].metadata["user-data-encoding"] == "base64"
    error_message = "user-data-encoding=base64 makes cloud-init decode it."
  }
}

run "bootstrap_cloud_config_gzip" {
  variables {
    # base64 of a gzip stream: starts with H4sI.
    bootstrap_data = "H4sIAAAAAAAAA1NWyEgtSk1RBABx0wMrCgAAAA=="
  }

  assert {
    condition     = nonsensitive(google_compute_instance.node_instance[0].metadata["user-data"]) == "H4sIAAAAAAAAA1NWyEgtSk1RBABx0wMrCgAAAA==" && google_compute_instance.node_instance[0].metadata["user-data-encoding"] == "base64"
    error_message = "gzipped cloud-config is passed as base64 too; cloud-init decompresses it."
  }
}

run "bootstrap_ignition" {
  variables {
    bootstrap_format = "ignition"
    # base64 of {"ignition":{"version":"3.4.0"}}
    bootstrap_data = "eyJpZ25pdGlvbiI6eyJ2ZXJzaW9uIjoiMy40LjAifX0="
  }

  assert {
    condition     = nonsensitive(google_compute_instance.node_instance[0].metadata["user-data"]) == "{\"ignition\":{\"version\":\"3.4.0\"}}"
    error_message = "Ignition reads user-data raw, so it is decoded."
  }
  assert {
    condition     = !contains(keys(google_compute_instance.node_instance[0].metadata), "user-data-encoding")
    error_message = "Ignition gets no user-data-encoding."
  }
}

run "rejects_gzipped_ignition" {
  command = plan

  variables {
    bootstrap_format = "ignition"
    bootstrap_data   = "H4sIAAAAAAAAA1NWyEgtSk1RBABx0wMrCgAAAA=="
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "bootstrap_too_large" {
  command = plan

  variables {
    # 262148 characters: 4 over the limit.
    bootstrap_data = format("%0262148d", 0)
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "rejects_image_placeholder_without_version" {
  command = plan

  variables {
    kubernetes_version = null
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "rejects_control_plane_zone_without_instance_group" {
  command = plan

  variables {
    control_plane = true
    captf_cluster_outputs = {
      schema      = "captf.io/gcp-cluster/v1"
      project     = "captf-test"
      region      = "us-central1"
      network     = "https://www.googleapis.com/compute/v1/projects/captf-test/global/networks/captf-vpc"
      subnetwork  = "https://www.googleapis.com/compute/v1/projects/captf-test/regions/us-central1/subnetworks/captf-nodes"
      name_prefix = "captf-team-a-demo-1d4e2f6a"
      failure_domains = {
        "us-central1-a" = { zone = "us-central1-a" }
        "us-central1-b" = { zone = "us-central1-b" }
        "us-central1-c" = { zone = "us-central1-c" }
        "us-central1-f" = { zone = "us-central1-f" }
      }
      node_network_tag = "captf-team-a-demo-1d4e2f6a-node"
      control_plane = {
        service_account = "captf-team-a-demo-1d4e2f6a-cp@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-control-plane"]
      }
      worker = {
        service_account = "captf-team-a-demo-1d4e2f6a-wk@captf-test.iam.gserviceaccount.com"
        network_tags    = ["captf-team-a-demo-1d4e2f6a-node", "captf-team-a-demo-1d4e2f6a-worker"]
      }
      api = {
        host            = "10.0.0.10"
        port            = 6443
        backend_port    = 6443
        instance_groups = {}
      }
    }
  }

  expect_failures = [google_compute_instance.node_instance]
}

run "instance_name_sanitized" {
  command = plan

  variables {
    machine_name = "1st.node.of.a-very-long-machine-name-that-goes-on-and-on-past-sixty-three"
  }

  assert {
    condition     = google_compute_instance.node_instance[0].name == "${substr("m-1st-node-of-a-very-long-machine-name-that-goes-on-and-on-past-sixty-three", 0, 54)}-${substr(sha256("1st.node.of.a-very-long-machine-name-that-goes-on-and-on-past-sixty-three"), 0, 8)}"
    error_message = "An invalid machine_name is made valid: a leading letter, - for invalid characters, 54 characters and a hash."
  }
}

run "secure_boot_off" {
  command = plan

  variables {
    secure_boot = false
  }

  assert {
    condition     = !google_compute_instance.node_instance[0].shielded_instance_config[0].enable_secure_boot && google_compute_instance.node_instance[0].shielded_instance_config[0].enable_vtpm
    error_message = "secure_boot turns off Secure Boot only."
  }
}

# Health: one run per mapped state. Each run replaces the instance, because
# a status override applies only when the instance is created.

run "health_running" {
  assert {
    condition     = output.health.state == "running" && output.health.healthy
    error_message = "RUNNING is running and healthy."
  }
}

run "health_pending" {
  plan_options {
    replace = [google_compute_instance.node_instance[0]]
  }

  override_resource {
    target = google_compute_instance.node_instance
    values = {
      current_status = "STAGING"
    }
  }

  assert {
    condition     = output.health.state == "pending" && !output.health.healthy && output.health.reasons == tolist(["InstanceStaging"])
    error_message = "STAGING is pending."
  }
}

run "health_degraded" {
  plan_options {
    replace = [google_compute_instance.node_instance[0]]
  }

  override_resource {
    target = google_compute_instance.node_instance
    values = {
      current_status = "REPAIRING"
    }
  }

  assert {
    condition     = output.health.state == "degraded" && !output.health.healthy
    error_message = "REPAIRING is degraded."
  }
}

run "health_stopped" {
  plan_options {
    replace = [google_compute_instance.node_instance[0]]
  }

  override_resource {
    target = google_compute_instance.node_instance
    values = {
      current_status = "TERMINATED"
    }
  }

  assert {
    condition     = output.health.state == "stopped" && !output.health.healthy && output.health.reasons == tolist(["InstanceTerminated"])
    error_message = "TERMINATED (Compute Engine's stopped) is stopped."
  }
}

run "health_terminated" {
  plan_options {
    replace = [google_compute_instance.node_instance[0]]
  }

  override_resource {
    target = google_compute_instance.node_instance
    values = {
      current_status = "DEPROVISIONING"
    }
  }

  assert {
    condition     = output.health.state == "terminated" && !output.health.healthy
    error_message = "DEPROVISIONING is terminated."
  }
}

run "health_unknown" {
  plan_options {
    replace = [google_compute_instance.node_instance[0]]
  }

  override_resource {
    target = google_compute_instance.node_instance
    values = {
      current_status = "SOMETHING_NEW"
    }
  }

  assert {
    condition     = output.health.state == "unknown" && !output.health.healthy && output.health.reasons == tolist(["UnknownState"])
    error_message = "A status the module does not know is unknown."
  }
}

# Validations, one run each.

run "invalid_captf_contract" {
  command = plan
  variables {
    captf_contract = "v1beta1"
  }
  expect_failures = [var.captf_contract]
}

run "invalid_bootstrap_delivery" {
  command = plan
  variables {
    bootstrap_delivery = "s3"
  }
  expect_failures = [var.bootstrap_delivery]
}

run "invalid_bootstrap_format" {
  command = plan
  variables {
    bootstrap_format = "shell"
  }
  expect_failures = [var.bootstrap_format]
}

run "invalid_additional_tags_count" {
  command = plan
  variables {
    additional_tags = { for i in range(59) : "k${i}" => "v" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_syntax" {
  command = plan
  variables {
    additional_tags = { team = "Platform" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_additional_tags_reserved" {
  command = plan
  variables {
    additional_tags = { "captf-io_kind" = "x" }
  }
  expect_failures = [var.additional_tags]
}

run "invalid_disk_kms_key" {
  command = plan
  variables {
    boot_disk_kms_key_id = "my-key"
  }
  expect_failures = [var.boot_disk_kms_key_id]
}

run "invalid_disk_size_gib" {
  command = plan
  variables {
    boot_disk_size_gib = 5
  }
  expect_failures = [var.boot_disk_size_gib]
}

run "invalid_disk_type" {
  command = plan
  variables {
    boot_disk_type = "ssd"
  }
  expect_failures = [var.boot_disk_type]
}

run "invalid_external_cluster_exports" {
  command = plan
  variables {
    external_cluster_exports = { schema = "captf.io/gcp-cluster/v2" }
  }
  expect_failures = [var.external_cluster_exports]
}

run "invalid_image_missing" {
  command = plan
  variables {
    image = null
  }
  expect_failures = [var.image]
}

run "invalid_image_whitespace" {
  command = plan
  variables {
    image = "my image"
  }
  expect_failures = [var.image]
}

run "invalid_machine_type" {
  command = plan
  variables {
    machine_type = "N2 Standard"
  }
  expect_failures = [var.machine_type]
}

run "invalid_additional_network_tags" {
  command = plan
  variables {
    additional_network_tags = ["Allow_SSH"]
  }
  expect_failures = [var.additional_network_tags]
}
