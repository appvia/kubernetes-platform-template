# Kubernetes Platform Template

## Overview

This repository provides a **template for consuming the [Appvia Kubernetes Platform](https://github.com/appvia/kubernetes-platform)**. It demonstrates how to define, provision, and manage tenant-specific EKS clusters using a GitOps-driven workflow.

The template serves as a starting point for teams who want to:

- **Define cluster configurations** as YAML files in `clusters/`
- **Provision AWS infrastructure** (VPC, EKS, networking) using Terraform
- **Bootstrap the platform** from the upstream Kubernetes Platform repository
- **Deploy workloads** via ArgoCD ApplicationSets sourced from this repository
- **Create their own distribution** by pointing to a forked tenant repository

Once a cluster is provisioned, the cluster definition YAML files are consumed by an ArgoCD ApplicationSet running on the platform. This means all subsequent cluster changes — workloads, configuration, feature toggles — are managed declaratively through Git.

---

## Directory Structure

```
.
├── clusters/                 # Cluster definition YAML files (single source of truth)
│   ├── dev.yaml              # Example: dev cluster definition
│   └── README.md             # Cluster definitions documentation
├── config/                   # Platform configuration overrides
│   ├── argo-cd/
│   │   └── all.yaml          # ArgoCD settings (e.g., reconciliation timeout)
│   └── kyverno_policies/
│       └── all.yaml          # Kyverno policy defaults (image registries, exclusions)
├── terraform/                # Terraform infrastructure code
│   ├── main.tf               # Core modules: network, eks, platform
│   ├── locals.tf             # Decodes cluster YAML definitions
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Terraform outputs
│   ├── providers.tf          # AWS, Helm, kubectl provider configs
│   ├── Makefile              # Terraform-specific targets (apply, destroy, lint, etc.)
│   └── values/               # Environment-specific tfvars files
│       ├── dev.tfvars        # Dev environment variables
│       └── sensitive.tfvars  # Sensitive values (gitignored)
├── workloads/                # Application workloads deployed to clusters
│   ├── applications/         # User application definitions
│   │   ├── hello-helm/       # Example: single Helm chart app
│   │   ├── hello-helm-many/  # Example: multiple Helm chart apps
│   │   ├── hello-kustomize/  # Example: Kustomize-based app
│   │   └── hello-custom/     # Example: external git repo app
│   └── system/               # System-level workloads
├── scripts/
│   └── make-local.sh         # Local Kind cluster provisioning script
├── Makefile                  # Root-level targets (local, dev, dev-destroy, etc.)
└── .github/                  # CI/CD workflows and Dependabot config
```

---

## Cluster Definitions

Cluster definitions live in `clusters/*.yaml` and are the **single source of truth** for each environment. Here is how a cluster definition is formed:

```yaml
# clusters/dev.yaml
cluster_name: dev # Name of the tenant cluster
cloud_vendor: aws # Cloud provider (aws, gcp, azure)
environment: dev # Environment identifier
cluster_type: standalone # standalone, hub, or spoke
tenant: tenant # Tenant name

# Tenant repository — this is YOUR repository that holds cluster config
tenant_repository: https://github.com/appvia/kubernetes-platform-template
tenant_revision: main # Branch, tag, or commit to use
tenant_path: "" # Optional sub-path within the tenant repo
tenant_cost_center: "123456" # Cost center metadata

# Platform repository — the upstream Kubernetes Platform
platform_repository: https://github.com/appvia/kubernetes-platform.git
platform_revision: main # Platform branch/tag to consume
platform_path: overlays/release # Kustomize overlay path in the platform repo

# Feature toggles — enable/disable platform components
labels:
  enable_aws_load_balancer: "true"
  enable_cert_manager: "true"
  enable_external_secrets: "true"
  enable_karpenter_nodepools: "true"
  enable_kyverno: "true"
  enable_kyverno_policies: "true"
  enable_metrics_server: "true"
  enable_gateway_api: "true"

# Annotations — additional metadata
annotations:
  storage_ebs_provisioner: ebs.csi.eks.amazonaws.com
  region: eu-west-2
```

### How It Works

1. **Terraform** reads the YAML via `yamldecode(file(var.cluster_path))` in `terraform/locals.tf`
2. The decoded values are passed to the `module "platform"` which bootstraps ArgoCD
3. After provisioning, the platform's **ApplicationSet** watches this repository and reconciles all `workloads/` and `config/` definitions
4. Changes to the YAML or workload files are automatically applied via GitOps

---

## Getting Started: Create Your Own Distribution

This repository is a **template** for consuming the [Kubernetes Platform](https://github.com/appvia/kubernetes-platform). The platform repository provides the reusable base components, while this template defines how you consume and configure it for your organization.

To create your own distribution:

### 1. Clone This Repository Into Your Organization

```bash
# Clone this template repository into your organization
git clone https://github.com/<your-org>/<your-tenant-repo>.git
cd <your-tenant-repo>
```

### 2. Update the Cluster Definition

Edit `clusters/dev.yaml` (or create new environment files) and change **`tenant_repository`** and **`tenant_revision`** to point to your cloned repository:

```yaml
# Point to YOUR organization's copy of this template
tenant_repository: https://github.com/<your-org>/<your-tenant-repo>.git
tenant_revision: main
```

- **`tenant_repository`** — The URL of your organization's repository. This is where ArgoCD will source workloads, configuration, and cluster definitions from.
- **`tenant_revision`** — The branch, tag, or Git commit SHA to use. Use `main` for the default branch, or pin to a specific commit for reproducibility.

> **Note:** The `platform_repository` field points to the upstream [Kubernetes Platform](https://github.com/appvia/kubernetes-platform) — this is the reusable base you consume. You only need to fork the platform repository if you want to extend or modify the platform itself. For most users, consuming the platform as-is and customizing this tenant repository is the recommended approach.

### 3. Customize Platform and Workloads

- Modify `config/` to set your organization's defaults (ArgoCD settings, Kyverno policies, etc.)
- Add your own application definitions under `workloads/applications/`
- Remove the example `hello-*` applications

### 4. Configure Terraform Variables

Edit `terraform/values/dev.tfvars` (or create new environment files):

```hcl
cluster_path = "../clusters/dev.yaml"
tags = {
  Environment   = "dev"
  Owner         = "your-team"
  Product       = "your-product"
}
```

For sensitive values (NAT gateway mode, transit gateway IDs, SSO roles), create `terraform/values/sensitive.tfvars` — this file is gitignored by default.

### 5. Commit and Push

```bash
git add .
git commit -m "feat: initial cluster definition for my-org"
git push -u origin main
```

---

## Deployment

### Local Development (Kind Cluster)

Provision a local Kubernetes cluster using Kind with ArgoCD bootstrapped.

- By default this uses the `dev` cluster definition.
- The revision used will be the currently checked out branch/commit of this repository.
- To development a change, you can create a new branch, make changes, push and validate from within Kind.

```bash
make local
```

This runs `scripts/make-local.sh` which:

1. Creates a Kind cluster named `dev`
2. Installs ArgoCD
3. Patches the bootstrap Application to use your `tenant_repository` and `tenant_revision`
4. Begins reconciling workloads from this repository

**Options:**

```bash
# Use a specific Git commit as the revision
make local USE_GIT_COMMIT=true

# Use a specific revision (branch/tag/SHA)
make local USE_REVISION=v1.0.0

# Specify a custom cluster name
make local CLUSTER_NAME=my-cluster
```

**Destroy the local cluster:**

```bash
make destroy-local
```

### Terraform-Based Deployment (AWS EKS)

Deploy to AWS using Terraform:

```bash
# Provision the dev environment
make dev

# Or run terraform targets directly
make -C terraform environment ENVIRONMENT=dev

# Destroy the dev environment
make dev-destroy
# Or: make -C terraform environment-destroy ENVIRONMENT=dev
```

The Terraform configuration provisions:

- **VPC and subnets** (via `module "network"`)
- **EKS cluster** with managed node groups (via `module "eks"`)
- **Platform bootstrap** — installs the Kubernetes Platform from the upstream repository and configures ArgoCD to watch this tenant repository (via `module "platform"`)

### Terraform Makefile Targets

| Target                                  | Description                                                |
| --------------------------------------- | ---------------------------------------------------------- |
| `make -C terraform environment`         | Apply infrastructure (uses `values/${ENVIRONMENT}.tfvars`) |
| `make -C terraform environment-destroy` | Destroy infrastructure                                     |
| `make -C terraform init`                | Initialize Terraform and all subdirectories                |
| `make -C terraform validate`            | Validate configuration                                     |
| `make -C terraform lint`                | Run tflint                                                 |
| `make -C terraform security`            | Run Trivy security scans                                   |
| `make -C terraform format`              | Format Terraform files                                     |
| `make -C terraform tests`               | Run Terraform tests                                        |
| `make -C terraform documentation`       | Generate documentation                                     |

### Root Makefile Targets

| Target               | Description                                        |
| -------------------- | -------------------------------------------------- |
| `make local`         | Provision local Kind cluster                       |
| `make dev`           | Deploy dev environment to AWS                      |
| `make dev-destroy`   | Destroy dev environment                            |
| `make destroy-local` | Delete local Kind cluster                          |
| `make all`           | Run lint, validate, tests, security, format, docs  |
| `make clean`         | Remove `.terraform/` directories and local cluster |

---

## Architecture

```
clusters/dev.yaml (cluster definition)
        │
        ├──► Terraform (AWS)                    scripts/make-local.sh (local)
        │    locals.tf: yamldecode()            grep tenant_repository / tenant_revision
        │         │                                      │
        │    ┌────┴──────────────┐                       │
        │    │                   │                       │
        │  network             eks                       │
        │  (VPC, subnets)    (EKS cluster)               │
        │    │                   │                       │
        │    └────────┬──────────┘                       │
        │             │                                  │
        │          platform                              │
        │   (appvia/eks/aws//modules/platform)           │
        │             │                                  │
        │             ▼                                  ▼
        │     ArgoCD ApplicationSet            ArgoCD bootstrap Application
        │     (GitOps loop)                    (JSON-patched with tenant values)
        │             │                                  │
        │             ├── workloads/applications/        ├── workloads/applications/
        │             ├── config/                        ├── config/
        │             └── platform_repository            └── platform_repository
        │                /platform_path                     /overlays/{type}
        │
        └──► After provisioning: ApplicationSet continuously reconciles
             this repository's workloads/ and config/ directories
```

---

## CI and release promotion

The [Validation workflow](.github/workflows/ci.yml) runs on pushes and pull requests to `main`. One of those jobs, **Validate Promotion** (`validate-promotion`), uses the [kubernetes-platform-promotion](https://github.com/appvia/appvia-cicd-workflows/blob/main/.github/actions/kubernetes-platform-promotion/README.md) composite action from [appvia-cicd-workflows](https://github.com/appvia/appvia-cicd-workflows).

### What `validate-promotion` enforces

For Helm workloads under `workloads/applications`, each environment file (for example `dev.yaml`, `staging.yaml`, `prod.yaml`) carries a `helm.version`. The action walks the configured **promotion order** and, for each changed env file, compares its version to the **nearest existing predecessor** environment in that order.

**Rule:** the changed environment’s version must **not be greater than** its predecessor’s version (`helm.version`). So with dev → staging → prod (or the full chain in CI), **production cannot declare a higher chart version than staging**, and **staging cannot be higher than dev**—unless you update the predecessor first (typically in the same pull request). A downstream env may still be **lower** than upstream while a promotion is in progress; the check blocks **skipping ahead** (for example landing `prod.yaml` at `2.0.0` while `staging.yaml` is still `1.0.0`).

Kustomize-only env files are skipped; Helm workloads without a valid semver can fail the check. See the action README for rules, edge cases, and the `promotion/skip-validation` label escape hatch for hotfixes.

This template sets `promotion-order` to `dev,qa,uat,staging,prod` in CI; adjust it in `.github/workflows/ci.yml` if your environments differ.

### Repository setup (recommended)

To make this meaningful in day-to-day merges:

1. **Branch protection on `main`** — Require pull requests before merging; do not allow direct pushes that bypass review.
2. **Required status checks** — Require the Validation workflow jobs to pass before merge, including **Validate Promotion** and the other checks (YAML, Terraform validate/lint, scripts, schema, and on PRs **Validate Commitlint**). In GitHub: **Settings → Branches → Branch protection rules → Require status checks to pass** — select each job name as it appears on pull requests (for example **Validate Promotion**, **Validate YAML**, **Lint Terraform**, **Validate Terraform**, **Validate Scripts**, **Validate Schema**, **Validate Commitlint**).
3. **Multiple reviewers** — Require **at least two approvals** (or your org’s equivalent) before merge so promotions are reviewed by more than one person.

Full input/output reference and examples: [kubernetes-platform-promotion action README](https://github.com/appvia/appvia-cicd-workflows/blob/main/.github/actions/kubernetes-platform-promotion/README.md).

---

## Further Reading

- [Cluster Definitions](clusters/README.md) — Details on cluster YAML files
- [Terraform Configuration](terraform/README.md) — Auto-generated Terraform documentation
- [Kubernetes Platform](https://github.com/appvia/kubernetes-platform) — The upstream platform repository
