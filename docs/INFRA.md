# Infrastructure Provisioning (Terraform)

`terraform/` provisions everything the app-level pipeline in
[DEPLOYMENT.md](DEPLOYMENT.md) assumes already exists: the AKS cluster
itself, plus ArgoCD and SonarQube running inside it. Run this **first**,
once, before following `DEPLOYMENT.md`.

## What it creates

| Resource | Purpose |
|---|---|
| `azurerm_resource_group.aks_rg` | Resource group holding the cluster |
| `azurerm_kubernetes_cluster.aks_cluster` | AKS cluster, `system` node pool |
| `azurerm_kubernetes_cluster_node_pool.user_pool` | Second `User`-mode node pool for workloads |
| `kubernetes_namespace.argocd` + `helm_release.argocd` | ArgoCD, official `argo-helm` chart, `argocd-server` exposed as `LoadBalancer` |
| `kubernetes_namespace.sonarqube` + `helm_release.sonarqube` | SonarQube, official SonarSource chart (bundled Postgres subchart), exposed as `LoadBalancer` on port 9000 |

## Prerequisites

- Terraform >= 1.5
- Azure CLI, logged in (`az login`) with a subscription selected
  (`az account set --subscription <id>`) and permissions to create
  resource groups / AKS clusters in it
- `kubectl` and `helm` installed locally (not strictly required by
  Terraform itself, but you'll want them immediately after for
  verification)

## Steps

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if you want different names/region/VM size

terraform init
terraform plan
terraform apply
```

This takes 10–15 minutes (AKS cluster creation + two Helm chart installs,
SonarQube's Elasticsearch startup is the slowest part).

## After apply

```bash
# Configure local kubectl/argocd CLI access
terraform output -raw get_credentials_command | bash
# or just:
az aks get-credentials --resource-group <rg> --name <cluster-name>

# Get ArgoCD's external IP and admin password
kubectl get svc argocd-argocd-server -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Get SonarQube's external IP (default login admin/admin, forced change on first login)
kubectl get svc sonarqube-sonarqube -n sonarqube
```

Once you have SonarQube's external IP, set it as `SONAR_HOST_URL`
(`http://<ip>:9000`) in the app repo's GitHub Secrets — see
[DEPLOYMENT.md](DEPLOYMENT.md) §2 — and create a SonarQube user token to use
as `SONAR_TOKEN`.

Then continue with `argocd/application.yaml` (in the repo root, not this
`terraform/` directory) as described in `DEPLOYMENT.md` §3 to point ArgoCD
at this app.

## Notes / deviations from the original manual setup

- The original setup installed ArgoCD by applying the raw upstream
  `install.yaml` via a Terraform `null_resource` + a separate imperative
  `kubectl apply` for the service patch. This module replaces both with a
  single `helm_release` resource — same result, but a real, trackable
  Terraform resource that `terraform destroy` can clean up properly. If
  you're migrating from that setup, `terraform import` the existing
  cluster or just `terraform destroy`/re-apply from clean, whichever suits
  your situation.
- SonarQube was previously **not actually deployed to this cluster** — the
  `sonarqube` namespace existed but was empty, and `SONAR_HOST_URL`
  pointed elsewhere. This module fixes that gap.
- SonarQube's bundled PostgreSQL subchart is fine for a POC. For anything
  longer-lived, point it at a managed Postgres instance instead (Azure
  Database for PostgreSQL) — set `postgresql.enabled = false` and the
  `jdbcOverwrite` values in `terraform/sonarqube.tf`.

## Tearing down

```bash
cd terraform
terraform destroy
```

This removes the AKS cluster and everything running on it, including the
`supermariogame-deployment` app if `argocd/application.yaml` was applied —
ArgoCD itself gets destroyed along with the cluster it's running on.
