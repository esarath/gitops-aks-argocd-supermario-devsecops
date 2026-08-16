# GitOps AKS ArgoCD SuperMario DevSecOps

A DevSecOps GitOps proof-of-concept: a browser-playable Mario clone,
containerized and deployed to Azure Kubernetes Service (AKS) through a
single CI/CD pipeline covering SAST (SonarQube), container image scanning
(Trivy), and continuous deployment (ArgoCD) — triggered by nothing more
than `git push`.

## Quickstart

New to this repo? Read in this order:

1. **[docs/HLD.md](docs/HLD.md)** — architecture, design decisions, why it's built this way.
2. **[docs/LLD.md](docs/LLD.md)** — pipeline internals, file layout, the security fixes applied.
3. **[docs/INFRA.md](docs/INFRA.md)** — Terraform: provisions the AKS cluster, ArgoCD, and SonarQube. Run this first, on a fresh environment.
4. **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** — exact step-by-step commands to deploy the app itself, plus a troubleshooting section built from real issues hit during development.

If you just want to get this running end-to-end with no surprises on a
brand-new environment: `docs/INFRA.md` first (provisions the cluster +
ArgoCD + SonarQube), then `docs/DEPLOYMENT.md` (deploys the app onto it).

## What's in here

```
terraform/                              IaC: AKS cluster + ArgoCD + SonarQube (Helm)
.github/workflows/ci-cd-pipeline.yaml   CI/CD: SAST -> build/push -> scan -> deploy
argocd/application.yaml                 ArgoCD Application manifest (apply once)
k8s/deployment.yaml                     Deployment + Service manifest template
webapp/                                 Game source (served by Tomcat)
Dockerfile                              Tomcat-based image build
package.json, jest.config.js            Jest test runner + coverage config
sonar-project.properties                SonarQube project config
docs/                                   HLD, LLD, infra, deployment guide
```

## Pipeline at a glance

```
push to main
  -> SAST scan + Quality Gate (SonarQube)
  -> build & push image (Docker Hub, tag = short git SHA)
  -> container vulnerability scan (Trivy)
  -> update deploy branch's k8s/deployment.yaml
  -> ArgoCD auto-syncs to AKS
```

One workflow file, four sequential jobs, no races. See
[docs/LLD.md](docs/LLD.md) §3 for why this matters (the original POC this
was migrated from had 4 separate workflow files, two of which raced each
other).

## Required GitHub Secrets

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) §2 for the full list and
where to set them. This repo's `argocd/application.yaml` is already
pointed at `https://github.com/esarath/gitops-aks-argocd-supermario-devsecops.git`.

## Migrated from

This repo consolidates and hardens a prior POC repo
(`gitops-practice-devsecops-sonarqube-sast-scan-supermario-repo`, now
archived). See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) §7 before deleting
that repo, if you're doing your own migration.

## Live environment (this instance)

Provisioned via `terraform/` on an Azure free-tier subscription — see
[docs/INFRA.md](docs/INFRA.md) §"Subscription tier matters" for the public
IP quota constraint that shaped a couple of the choices below (ArgoCD's
`ClusterIP` in particular; flip it back to `LoadBalancer` on Pay-As-You-Go):

| | |
|---|---|
| AKS cluster | `gitopsSupermarioAks` (resource group `gitops-supermario-rg`, `eastus2`) |
| Game | publicly reachable, `LoadBalancer` service |
| ArgoCD | `ClusterIP` — reach via `kubectl port-forward svc/argocd-server -n argocd 8080:80` |
| SonarQube | publicly reachable, `LoadBalancer` service on port 9000 |
