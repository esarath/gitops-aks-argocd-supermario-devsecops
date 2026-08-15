# High-Level Design (HLD)

## 1. Purpose

This project is a DevSecOps GitOps proof-of-concept: a static browser game
("Infinite Mario") is containerized, security-scanned at two layers (source
code and container image), and continuously deployed to Azure Kubernetes
Service (AKS) via ArgoCD — with zero manual `kubectl apply` in the normal
flow.

## 2. Architecture Overview

```
Developer
   |
   |  git push (main)
   v
GitHub Actions (ci-cd-pipeline.yaml)
   |
   |-- 1. SAST scan (SonarQube) -------- source code quality + security gate
   |-- 2. Build & push image ----------- Docker Hub, tag = short git SHA
   |-- 3. Container scan (Trivy) ------- CRITICAL/HIGH CVEs, tarball-free
   |-- 4. Update `deploy` branch ------- k8s/deployment.yaml image tag bump
   v
GitHub `deploy` branch (desired state)
   |
   |  polled every ~3 min (or on-demand refresh)
   v
ArgoCD (running in AKS, namespace `argocd`)
   |
   |  auto-sync + self-heal
   v
AKS cluster
   |-- Deployment: supermariogame-deployment
   |-- Service:    supermariogame-service (LoadBalancer)
   v
Public IP:8600 --> Player's browser
```

## 3. Key Design Decisions

| Decision | Rationale |
|---|---|
| **Two branches**: `main` (source + CI definitions) and `deploy` (desired k8s state) | Keeps ArgoCD's watched path free of unrelated app-source churn; every commit to `deploy` is a deployable, atomic change. |
| **Image tag = short git SHA**, not a hand-maintained version counter | SHA tags are unique, traceable to an exact commit, and require no shared mutable counter file (avoids race conditions between concurrent pipeline runs). |
| **Single sequential pipeline** (`sast_scan` → `build_and_push_image` → `scan_image` → `update_deploy_branch`), not multiple independently-triggered workflows | The original POC had 4 separate workflow files, two of which both ran a SonarQube scan on the same push and raced each other, and one of which updated a branch nothing watched. A single job-chained workflow removes both problems by construction. |
| **Trivy scans the pushed image by reference** (`image-ref`), not a locally-saved `.tar` | Avoids container-action workspace mount path mismatches (root-caused a real "file not found" failure during POC development) and drops the extra pull/save/login steps. |
| **`exit-code: '0'` on Trivy** | Vulnerabilities are reported, not blocking, for this POC. Flip to `'1'` once the team is ready to gate merges on CVE findings. |
| **ArgoCD `selfHeal: true`** | Any manual/out-of-band change to the live Deployment is reverted automatically — the `deploy` branch is the only source of truth. |
| **jQuery vendored into the image**, not loaded from a CDN | The original `index.html` loaded jQuery from `ajax.googleapis.com`. On networks that block that CDN, the game's entire init (`$(document).ready(...)`) silently never fires, producing a blank page with no console error. Bundling removes the external dependency. |

## 4. Components

| Component | Responsibility |
|---|---|
| **GitHub Actions** | CI: test, SAST, build, container scan, GitOps manifest update. |
| **SonarQube** (self-hosted or SonarCloud) | Static analysis + Quality Gate (coverage, security hotspots, ratings). |
| **Docker Hub** | Container image registry. |
| **Trivy** | Container image vulnerability scanner (CVE database). |
| **ArgoCD** | Continuous deployment controller inside AKS; polls `deploy` branch. |
| **AKS** | Runtime — 1 Deployment, 1 Service (`LoadBalancer`), namespace `default`. |

## 5. Security Posture (as of this POC)

- Source-level: command injection, hardcoded credentials, weak hashing
  (SHA-1/MD5), synchronous XHR, IDOR, and SQL injection patterns were
  identified and fixed in `webapp/code/multiple.js` — see [LLD](LLD.md) §4.
- Pipeline-level: `permissions: contents: write` is scoped at the workflow
  level (not broader); Docker Hub and SonarQube credentials are GitHub
  Secrets, never hardcoded.
- Runtime: container runs on Tomcat's default (non-root can be hardened
  further — see [LLD](LLD.md) §6 open items).

## 6. Out of Scope (for this POC)

- AKS cluster + ArgoCD installation itself (provisioned separately via
  Terraform in a companion infra repo — not duplicated here).
- Ingress/TLS termination (Service is a bare `LoadBalancer` on port 8600).
- Multi-environment (staging/prod) promotion — single `deploy` branch only.
