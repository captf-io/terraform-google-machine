# Examples

Manifests that use the gcp module images, which are built by
[module-images](https://github.com/captf-io/module-images) from this repository's releases. The same two
files are in each of the three role repositories. Both are
[clusterctl](https://cluster-api.sigs.k8s.io/clusterctl/overview) templates:
`clusterctl generate yaml --from <file>` fills the `${VARIABLE}`
placeholders from the environment, with the defaults after `:=`.

| File | What | Variables |
| --- | --- | --- |
| [identity.yaml](identity.yaml) | The credentials Secret (placeholder values) and the `TerraformClusterIdentity` naming it; admin-applied once | `NAMESPACE`, `GCP_PROJECT`, `GCP_REGION`, `TERRAFORM_IDENTITY_NAME` |
| [cluster-kubeadm.yaml](cluster-kubeadm.yaml) | A kubeadm cluster: TerraformCluster (internal API endpoint), KubeadmControlPlane, a MachineDeployment, an autoscaled MachinePool and MachineHealthChecks | `CLUSTER_NAME`, `KUBERNETES_VERSION`, `GCP_NETWORK`, `GCP_SUBNETWORK`, `GCP_IMAGE`; optional `CONTROL_PLANE_MACHINE_COUNT`, `WORKER_MACHINE_COUNT`, `GCP_WORKER_MACHINE_TYPE`, `POOL_MIN_SIZE`, `POOL_MAX_SIZE`, `POD_CIDR`, `SERVICE_CIDR`, `TERRAFORM_IDENTITY_NAME` |

The manifests pin every image to a release, `v0.1.0-opentofu`: change the
tag to the release you deploy (`vX.Y.Z-opentofu` or `vX.Y.Z-terraform`), or
to a digest. The moving tags (`opentofu`, `terraform`) are
for trying things out, never for anything you keep.

The images reference a network and node images that must exist first; see
the [README](../README.md#prerequisites).
