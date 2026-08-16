# Deployment Guide (Step by Step)

Follow this exactly, in order, for a clean run with no surprises. Every
step here was hit-tested against a real failure encountered while building
this POC — the "why" notes are there so you don't have to re-debug them.

## 0. Prerequisites

- An AKS cluster already provisioned, with ArgoCD and SonarQube already
  installed on it. **Run [docs/INFRA.md](INFRA.md) first** if you haven't
  — it's the Terraform module that creates all of this from nothing.
  `kubectl config current-context` should show your AKS context once done.
- A Docker Hub account + access token (**Read & Write** scope — a
  read-only token fails at the push step with `unauthorized: access token
  has insufficient scopes`, easy to pick by accident since some Docker Hub
  UI flows default to read-only).
- SonarQube reachable from GitHub Actions runners, with a project created
  for this repo (INFRA.md walks through this via API).
- `gh` CLI authenticated (`gh auth status`) with the **`workflow`** OAuth
  scope — pushing a repo that includes a `.github/workflows/*.yaml` file
  fails otherwise with `refusing to allow an OAuth App to create or update
  workflow ... without workflow scope`. Fix ahead of time with:
  `gh auth refresh -h github.com -s workflow`.
- push access to a new GitHub repo you'll create.

## 1. Create the GitHub repo and push this code

```bash
cd gitops-aks-argocd-supermario-devsecops
git init
git add .
git commit -m "Initial commit: GitOps DevSecOps SuperMario POC"
gh repo create <your-github-username>/gitops-aks-argocd-supermario-devsecops --public --source=. --push
```

Then create the `deploy` branch (bootstrapped automatically on the first
pipeline run too, but creating it explicitly avoids a first-run edge case):

```bash
git checkout -b deploy
git push origin deploy
git checkout main
```

## 2. Configure GitHub Secrets

Repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not your password) |
| `SONAR_HOST_URL` | Your SonarQube server URL, e.g. `http://<sonarqube-external-ip>:9000` |
| `SONAR_TOKEN` | SonarQube user token (INFRA.md §"After apply" shows how to generate one) |
| `GIT_EMAIL` | Commit author email for automated `deploy` branch commits |
| `GIT_USERNAME` | Commit author name for automated `deploy` branch commits |

**No further permissions setup needed** — `permissions: contents: write`
is already declared in the workflow, so the default `GITHUB_TOKEN` can push
to `deploy` without a PAT.

## 3. Point `argocd/application.yaml` at your repo

Edit `argocd/application.yaml` — replace
`https://github.com/<your-github-username>/gitops-aks-argocd-supermario-devsecops.git`
with your actual repo URL. Then apply it once:

```bash
kubectl apply -f argocd/application.yaml -n argocd
```

Verify:

```bash
kubectl get application supermariogamedeployment -n argocd
# Expect SYNC STATUS eventually "Synced", HEALTH STATUS "Healthy"
```

If it doesn't sync within ~3 minutes (ArgoCD's default poll interval),
force it:

```bash
kubectl annotate application supermariogamedeployment -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

## 4. Trigger the pipeline

Any push to `main` runs it. For a first run, an empty commit works:

```bash
git commit --allow-empty -m "Trigger initial pipeline run"
git push origin main
```

Watch it:

```bash
gh run watch --exit-status
```

Expected job order: `sast_scan` → `build_and_push_image` → `scan_image` →
`update_deploy_branch`. All four must succeed for the `deploy` branch to
get updated.

## 5. Verify the game is live

```bash
kubectl get svc supermariogame-service
# note the EXTERNAL-IP
curl -I http://<EXTERNAL-IP>:8600/
```

Open `http://<EXTERNAL-IP>:8600/` in a browser. Hard refresh
(`Ctrl+Shift+R`) if you've loaded this URL before in that browser, to
bypass any cached response from a prior deploy.

## 6. Troubleshooting (issues actually hit during this POC)

**`gh repo create ... --push` fails: "refusing to allow an OAuth App to create or update workflow ... without workflow scope"**
Your `gh` token lacks the `workflow` OAuth scope, required to push any
file under `.github/workflows/`. Run
`gh auth refresh -h github.com -s workflow` (opens a browser to
re-authorize), then retry the push — no need to recreate the repo, it
already exists at this point, just push again.

**SonarQube Scan step fails: "You're not authorized to run analysis. Please contact the project administrator."**
The `SONAR_TOKEN` doesn't have access to the project key in
`sonar-project.properties` — either the project doesn't exist yet on your
SonarQube server (create it first, see INFRA.md §"After apply"), or the
token belongs to a different project/doesn't have provisioning rights.
Easiest fix for a fresh SonarQube instance: create the project via the API
call in INFRA.md before the first pipeline run.

**`docker push` fails: "unauthorized: access token has insufficient scopes"**
`DOCKERHUB_TOKEN` was generated with **Read-only** permission. Docker Hub
token creation doesn't always default to Read & Write — double check the
permission dropdown when generating it, regenerate if needed, and
`gh secret set DOCKERHUB_TOKEN --repo <owner>/<repo>` again. Also confirm
the token was generated under the **same Docker Hub account** as
`DOCKERHUB_USERNAME` — a token from a different account produces this
exact same error.

**`terraform apply` fails: `ErrCode_InsufficientVCPUQuota`**
Free/trial Azure subscriptions have very low (sometimes zero spare) vCPU
quota per region. See INFRA.md §"Subscription tier matters" — either free
quota by deleting an unused cluster first, pick a region with spare
quota, or request an increase (fast/automatic on Pay-As-You-Go, may not be
grantable on free/trial tiers at all).

**AKS LoadBalancer services stuck `<pending>` forever, events show `PublicIPCountLimitReached`**
Same root cause as above but for public IPs, not vCPUs — free-tier
subscriptions cap at 3 public IPs per region, one of which AKS reserves
for itself, leaving 2 for your own services. If you're running ArgoCD +
SonarQube + the game all as `LoadBalancer`, that's 3 wanted against a
budget of 2. This repo's Terraform defaults ArgoCD to `ClusterIP` for
exactly this reason — see INFRA.md. If a service is stuck pending after
freeing an IP, force a resync: `kubectl delete svc <name>` then
`kubectl apply -f k8s/deployment.yaml` (or let ArgoCD's self-heal recreate
it automatically within its next sync cycle).

**`terraform apply` fails: "Saved plan is stale"**
Something changed the state since the plan file was generated (commonly:
a previous `apply` partially succeeded, e.g. created the resource group
before failing on a later resource). Just re-run `terraform apply`
directly instead of `terraform apply "<planfile>"` — it computes a fresh
plan against current state.

**`terraform apply` fails: `OIDCIssuerFeatureCannotBeDisabled`**
Already fixed in this repo's `terraform/aks.tf`
(`oidc_issuer_enabled = true`, see INFRA.md for why). If you see this
anyway, someone removed that line.

**SonarQube's `sonarqube-postgresql-0` pod stuck `ImagePullBackOff`**
Bitnami removed the pinned Postgres image tag this chart version defaults
to. Already fixed in `terraform/sonarqube.tf`
(`postgresql.image.tag = "latest"`), see INFRA.md for the full
explanation. If you see this anyway, check
`kubectl describe pod sonarqube-postgresql-0 -n sonarqube` for the exact
tag it's failing to pull.

**SonarQube Quality Gate fails with unrelated coverage error**
`new_coverage`/`line_coverage` conditions require test coverage data.
`sonar-project.properties` already points at `coverage/lcov.info` and the
pipeline runs `npm test` before the scan — if the gate still fails on
`line_coverage`, it's a **project-wide** threshold, not a new-code one; see
LLD §3.1/§6. Either add more tests or adjust that condition in the
SonarQube UI (Quality Gates → your gate → edit conditions).

**Two SonarQube scans race each other on the same push**
Only happens if you've duplicated the SAST job into a second workflow file
triggered on the same `push: main` event — don't. This repo intentionally
has exactly one workflow file with a single `sast_scan` job.

**Trivy: `unable to open .../supermariolatestdockerimage.tar: no such file or directory`**
Already fixed here by scanning `image-ref` instead of a saved tarball (see
LLD §3.3). If you ever revert to tarball mode, expect this failure.

**`git push` to `deploy` fails with "Updates were rejected... fetch first"**
Someone (a previous pipeline run, or you manually) pushed to `deploy`
after the checkout in this job. Re-run the job — it re-checks out
`origin/deploy` fresh each time so this self-resolves. If it's a genuine
manual edit you want to keep, `git pull --rebase` before investigating
further (but see the branching-model rule in LLD §2 — you shouldn't be
editing `deploy` by hand).

**ArgoCD shows `Synced`/`Healthy` but the browser still shows the old game version**
Browser cache. Hard refresh. ArgoCD's sync status reflects the cluster's
actual state; if `kubectl get deployment supermariogame-deployment -o
jsonpath='{.spec.template.spec.containers[0].image}'` shows the new tag,
the deploy worked — this is a client-side caching issue, not a pipeline
one.

**Game loads (canvas visible) but shows a black screen with no console errors**
1. Confirm it's not just the ~1-second `LoadingState` fade transition
   (expected, resolves itself).
2. Hard refresh — stale cached `index.html`/`jquery.min.js` from before a
   fix was deployed is the most common cause.
3. Check DevTools Network tab for any request stuck **pending** (not
   404 — genuinely hung) — `LoadingState.Update` waits for every image's
   `.complete` flag before transitioning to the title screen, so one
   hung request blocks the whole game indefinitely.

**Blank page, no visible canvas fallback text either, no console errors**
Check whether jQuery loaded — this repo vendors `webapp/jquery.min.js` and
loads it locally specifically because CDN-loaded jQuery
(`ajax.googleapis.com`) is blocked on some networks, which causes exactly
this symptom (game init never runs, no error is thrown because the
`<script src="...">` tag itself just silently fails to fetch on some
network/extension configurations). If you're working from a fork that
reverted this, re-apply the fix: change `index.html`'s jQuery `<script
src>` to `jquery.min.js` and commit the vendored file.

## 7. Cleaning up an old POC repo (if migrating, as this one is)

Once this new repo is confirmed working end-to-end (steps 1–5 above all
green, game verified in-browser):

1. Update `argocd/application.yaml`'s `repoURL` (done in step 3) and
   confirm ArgoCD is pointed at the **new** repo — check
   `kubectl get application supermariogamedeployment -n argocd -o
   jsonpath='{.spec.source.repoURL}'`.
2. Only after that returns the new repo's URL, archive or delete the old
   POC repo. Don't delete it first — ArgoCD needs somewhere to sync from
   until the new `Application` resource is confirmed pointing elsewhere.
