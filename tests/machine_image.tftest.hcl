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

# Image placeholder tests of the machine role. Every run is a plan, so the
# state stays empty and each run plans a new instance: an existing instance
# ignores image changes (node_instance.tf).

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

run "image_placeholders" {
  command = plan

  variables {
    image              = "projects/p/global/images/a-{version}-b-{semver}-c-{slug}"
    kubernetes_version = "v1.31.4+rke2r1"
  }

  assert {
    condition     = google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].image == "projects/p/global/images/a-v1.31.4-b-1.31.4-c-v1-31-4"
    error_message = "Placeholders are replaced, with the +rke2rN suffix stripped."
  }
}


run "image_without_placeholder" {
  command = plan

  variables {
    image              = "projects/captf-images/global/images/family/capi-ubuntu-2404-k8s-v1-33"
    kubernetes_version = null
  }

  assert {
    condition     = google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].image == "projects/captf-images/global/images/family/capi-ubuntu-2404-k8s-v1-33"
    error_message = "An image without placeholders is used as it is."
  }
}


run "image_fullslug" {
  command = plan

  variables {
    image              = "projects/p/global/images/rke2-{fullslug}"
    kubernetes_version = "v1.31.4+rke2r2"
  }

  assert {
    condition     = google_compute_instance.node_instance[0].boot_disk[0].initialize_params[0].image == "projects/p/global/images/rke2-v1-31-4-rke2r2"
    error_message = "{fullslug} keeps the build suffix."
  }
}
