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
| `kubernetes_namespace.argocd` + `helm_release.argocd` | ArgoCD, official `argo-helm` chart, `argocd-server` exposed as `ClusterIP` by default (see §"Subscription tier" below) |
| `kubernetes_namespace.sonarqube` + `helm_release.sonarqube` | SonarQube, official SonarSource chart (bundled Postgres subchart), exposed as `LoadBalancer` on port 9000 |

## Prerequisites

- Terraform >= 1.5
- Azure CLI, logged in (`az login`) with a subscription selected
  (`az account set --subscription <id>`) and permissions to create
  resource groups / AKS clusters in it
- `kubectl` and `helm` installed locally (not strictly required by
  Terraform itself, but you'll want them immediately after for
  verification)

## Subscription tier matters: free/trial vs Pay-As-You-Go

This module was built and tested against a **free/trial Azure
subscription**, which caps public IPs at **3 per region** — and AKS itself
permanently reserves one of those three for node outbound traffic, leaving
only **2** for your own `LoadBalancer` services. ArgoCD + SonarQube + the
game's `supermariogame-service` is 3 wanted public IPs against a budget of
2, so `terraform/argocd.tf` defaults `server.service.type` to `ClusterIP`
(admin access via `kubectl port-forward`, see below) to leave both spare
IPs for SonarQube and the game — the two services that actually need to be
reachable by other people.

**On a Pay-As-You-Go (or any non-free-tier) subscription, this constraint
doesn't exist** — request a quota increase is rarely even necessary; PAYG
subscriptions typically start with a much higher default public IP quota
per region. If you're on PAYG:

1. In `terraform/argocd.tf`, change the `server.service.type` value from
   `"ClusterIP"` back to `"LoadBalancer"` (the comment above it in that
   file explains the trade-off).
2. Re-run `terraform apply` — ArgoCD's UI gets its own public IP like the
   other two services, no port-forward needed.
3. If you still hit `PublicIPCountLimitReached` on PAYG (unlikely, but
   possible on a brand-new subscription with default quotas), request a
   quota increase: Azure Portal → Subscriptions → your subscription →
   Usage + quotas → search "Public IP Addresses - Basic" → Request
   increase for your region. This is typically auto-approved within
   minutes on PAYG, unlike free/trial tiers where it may not be grantable
   at all.

To check your current usage/limit before deciding:

```bash
az network list-usages --location <region> \
  --query "[?name.value=='PublicIPAddresses']" -o table
```

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

# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# ArgoCD UI access — ClusterIP by default (see subscription-tier note above),
# so reach it via port-forward:
kubectl port-forward svc/argocd-server -n argocd 8080:80
# then open https://localhost:8080 (self-signed cert, expect a browser warning)
# If you flipped server.service.type to LoadBalancer (PAYG), use instead:
kubectl get svc argocd-server -n argocd

# Get SonarQube's external IP
kubectl get svc sonarqube-sonarqube -n sonarqube
```

SonarQube ships with a default `admin`/`admin` login that **must** be
changed before the instance is usable for anything beyond that first
login — either through the UI on first visit, or headlessly via its API
(useful for scripting a fresh environment end-to-end):

```bash
SONAR_IP=<from the command above>
NEW_PASSWORD='<pick something strong>'

curl -s -u admin:admin -X POST "http://$SONAR_IP:9000/api/users/change_password" \
  --data-urlencode "login=admin" \
  --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=$NEW_PASSWORD"

# Create the project this repo's sonar-project.properties expects
curl -s -u admin:"$NEW_PASSWORD" -X POST "http://$SONAR_IP:9000/api/projects/create" \
  --data-urlencode "project=gitopsdevsecopspipeline" \
  --data-urlencode "name=gitopsdevsecopspipeline"

# Generate a CI token (this is what goes into the SONAR_TOKEN secret)
curl -s -u admin:"$NEW_PASSWORD" -X POST "http://$SONAR_IP:9000/api/user_tokens/generate" \
  --data-urlencode "name=ci-cd-pipeline-token"
# -> copy the "token" field from the JSON response
```

Then set both `SONAR_HOST_URL` (`http://<SONAR_IP>:9000`) and
`SONAR_TOKEN` (the token just generated) in the app repo's GitHub Secrets
— see [DEPLOYMENT.md](DEPLOYMENT.md) §2.

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
- The SonarQube chart's bundled Postgres subchart defaults to a pinned
  Bitnami image tag (`11.14.0-debian-10-r22`) that Bitnami removed from
  Docker Hub after their 2025 catalog restructuring (versioned tags are
  now paywalled — only `latest` remains free). `terraform/sonarqube.tf`
  overrides `postgresql.image.tag` to `latest` to work around this. If
  Bitnami changes this again, `helm_release.sonarqube` will fail with
  `ImagePullBackOff` on the `sonarqube-postgresql-0` pod — check
  `kubectl describe pod sonarqube-postgresql-0 -n sonarqube` for the exact
  image it's trying (and failing) to pull.
- `azurerm_kubernetes_cluster` explicitly sets `oidc_issuer_enabled =
  true`. AKS enables this by default on new clusters regardless of what
  Terraform requests; leaving it undeclared causes every subsequent
  `terraform apply` to try to "correct" it back to disabled, which Azure
  rejects (`OIDCIssuerFeatureCannotBeDisabled`) — an infinite plan/apply
  drift loop. Declaring it explicitly avoids that.

## Tearing down

```bash
cd terraform
terraform destroy
```

This removes the AKS cluster and everything running on it, including the
`supermariogame-deployment` app if `argocd/application.yaml` was applied —
ArgoCD itself gets destroyed along with the cluster it's running on.
