# Cluster roles

Example workload showing how to grant **custom Kubernetes permissions** to IAM Identity Center (SSO) principals on EKS.

EKS access is configured in two places that work together:

1. **Cluster RBAC (this workload)** — define `ClusterRole` resources and bind them to Kubernetes groups via `ClusterRoleBinding`.
2. **Terraform access entries** — map an SSO IAM role ARN to one or more `kubernetes_groups` so EKS authenticates those principals as members of the bound group.

## How it fits together

When a user signs in through SSO and assumes an IAM role, EKS resolves the role via an [access entry](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html). If the entry lists `kubernetes_groups`, the principal is treated as a member of those groups and inherits whatever RBAC bindings exist for them.

```
SSO permission set  →  IAM role ARN  →  EKS access entry (kubernetes_groups)
                                              ↓
                              ClusterRoleBinding (group → ClusterRole)
                                              ↓
                                    Kubernetes API permissions
```

Administrators can instead use EKS **managed access policies** (see `terraform/settings.access.tf`), which attach AWS-defined policies such as `AmazonEKSClusterAdminPolicy`. Custom roles in this workload are for finer-grained permissions that managed policies do not cover.

## Terraform: bind SSO to a Kubernetes group

Add entries via the `access_entries` variable (merged in [`terraform/settings.access.tf`](../../../terraform/settings.access.tf)). Each key is a label for Terraform; `principal_arn` must be the SSO-reserved IAM role for the permission set.

```hcl
access_entries = {
  platform_ops = {
    principal_arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/eu-west-2/AWSReservedSSO_PlatformOps_abcdef1234567890"
    kubernetes_groups = ["system-nodeamanager"]
  }
}
```

Pass this through your tfvars (for example `terraform/values/dev.tfvars`) or whichever mechanism you use to supply Terraform variables. Replace the account ID, region segment, and role suffix with the values from your SSO permission set in IAM.

The `kubernetes_groups` value must match the group name used in a `ClusterRoleBinding` subject in this workload (see `base/cluster-bindings.yaml`).

## Kubernetes: define roles and bindings

Under `base/`:

- **`cluster-roles.yaml`** — `ClusterRole` definitions (for example node management for Karpenter, read-only secret access).
- **`cluster-bindings.yaml`** — `ClusterRoleBinding` resources that attach those roles to Kubernetes groups.

After enabling this workload (rename `kustomize.yaml.disabled` to `kustomize.yaml` and set the feature label in your cluster definition), Argo CD deploys the RBAC primitives before SSO principals need them.

## Example in this repo

| Kubernetes group     | ClusterRole                 | Intended use                                     |
| -------------------- | --------------------------- | ------------------------------------------------ |
| `platform-viewer`    | read-only secrets           | Broad read-only access for SSO viewers           |
| `platform-add-nodes` | node / Karpenter management | Ops staff who manage worker nodes and node pools |

Wire an SSO permission set to `platform-add-nodes` using the Terraform snippet above; users with that permission set then receive the permissions defined on the corresponding `ClusterRole`.

Further background: [platform cluster roles documentation](https://github.com/appvia/kubernetes-platform/blob/main/docs/docs/platform/security/cluster-roles.md).
