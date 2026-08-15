# Low-Level Design (LLD)

## 1. Repository Layout

```
.
├── .github/workflows/ci-cd-pipeline.yaml   # single CI/CD pipeline (see §3)
├── argocd/application.yaml                 # ArgoCD Application manifest (apply once, manually)
├── k8s/deployment.yaml                     # Deployment + Service (source template on main)
├── webapp/                                 # game source, served by Tomcat
│   ├── index.html
│   ├── jquery.min.js                       # vendored, not CDN-loaded
│   ├── code/                               # game engine + demo vulnerable-code files
│   │   ├── multiple.js                     # fixed + unit tested (see §4)
│   │   └── multiple.test.js
│   ├── Enjine/                             # game engine core
│   ├── images/, sounds/
├── Dockerfile
├── package.json / jest.config.js           # Jest test runner + coverage
├── sonar-project.properties
└── docs/
    ├── HLD.md
    ├── LLD.md (this file)
    └── DEPLOYMENT.md
```

## 2. Branching Model

| Branch | Purpose | Who writes to it |
|---|---|---|
| `main` | App source, CI pipeline definition, `k8s/deployment.yaml` **template** (placeholder tag `init`) | Developers, via PR/push |
| `deploy` | Desired live-cluster state — `k8s/deployment.yaml` with the **real, current** image tag | Only the CI pipeline (`update_deploy_branch` job), via `[skip ci]` commits |

ArgoCD's `Application.spec.source.targetRevision` is `deploy`, `path` is
`k8s`. Never edit `deploy` by hand — the next pipeline run or ArgoCD
self-heal will overwrite manual changes.

## 3. Pipeline Detail (`ci-cd-pipeline.yaml`)

Trigger: `push` to `main`.

```
sast_scan
   └─▶ build_and_push_image
          └─▶ scan_image
                 └─▶ update_deploy_branch
```

### 3.1 `sast_scan`
1. Checkout with `fetch-depth: 0` (SonarQube needs full history for blame/new-code detection).
2. `npm install`, `npm test` — runs Jest with `--coverage`, produces `coverage/lcov.info`.
3. `sonarsource/sonarqube-scan-action` — pushes analysis + the LCOV report (path configured in `sonar-project.properties`) to the SonarQube server.
4. `sonarsource/sonarqube-quality-gate-action` — polls the server, fails the job (and pipeline) if the Quality Gate is red.

**Coverage caveat**: only `webapp/code/multiple.js` has unit tests
(`collectCoverageFrom` in `jest.config.js` is scoped to it deliberately).
The rest of the game engine (`level.js`, `character.js`, etc.) has zero
tests. If your SonarQube Quality Gate has a **project-wide** `line_coverage`
condition (not just `new_coverage` on changed lines), it will stay red
until either (a) more tests are added, or (b) that specific condition is
relaxed for this repo in the SonarQube UI (Quality Gates → your gate →
remove/adjust `line_coverage`). This was hit during POC development —
see [DEPLOYMENT.md](DEPLOYMENT.md) §6 troubleshooting.

### 3.2 `build_and_push_image`
1. `id: version` step sets `GITHUB_OUTPUT.version = ${GITHUB_SHA::7}` (7-char short SHA).
2. Docker login via `secrets.DOCKERHUB_USERNAME` / `secrets.DOCKERHUB_TOKEN`.
3. `docker build` + `docker push` tagged `docker.io/<username>/supermariogitopsproject:<sha>`.
4. Exposes `version` as a job output consumed by both downstream jobs (`needs.build_and_push_image.outputs.version`) — this is the fix for GitHub Actions `env:` blocks **not** being shell-evaluated; a literal `$(( $(cat version.txt) + 1 ))` string in `env:` does not compute anything (this bug existed in the original POC pipeline and is deliberately avoided here).

### 3.3 `scan_image`
- `aquasecurity/trivy-action` scans the image **by reference**
  (`image-ref: docker.io/.../supermariogitopsproject:<sha>`), not a locally
  saved tarball. Trivy pulls it itself.
- Rationale: an earlier tarball-based approach (`docker pull` + `docker save`
  + `trivy --input <tar>`) failed in CI with
  `unable to open .../supermariolatestdockerimage.tar: no such file or directory`
  — a container-action workspace-mount path mismatch. Scanning by reference
  removes the whole failure class.
- `exit-code: '0'` — non-blocking. Change to `'1'` to fail the pipeline on
  CRITICAL/HIGH findings.

### 3.4 `update_deploy_branch`
1. Checkout `main`, configure git identity from `secrets.GIT_USERNAME` /
   `secrets.GIT_EMAIL` (author metadata only — actual push auth is the
   default `GITHUB_TOKEN`, granted `contents: write` at the workflow level).
2. `git checkout -B deploy origin/deploy` (or `origin/main` if `deploy`
   doesn't exist yet — bootstraps it on first run).
3. `sed -i` replaces the image line in `k8s/deployment.yaml` with the new
   SHA tag.
4. Commit with `[skip ci]` (prevents an infinite pipeline loop — this push
   would otherwise re-trigger `on: push: branches: [main]`... note it
   pushes to `deploy`, not `main`, so `[skip ci]` here is precautionary/
   documentation of intent rather than strictly required by the current
   trigger, but keep it if you ever add `deploy` as a trigger branch).
5. `git push origin HEAD:deploy`.

## 4. `multiple.js` — Security Fixes (unit-tested)

This file is a deliberate catalog of vulnerable patterns used to exercise
the SAST scanner. Each was fixed and covered by `multiple.test.js`:

| Vulnerability | Before | After |
|---|---|---|
| Command injection | `exec(command, ...)` with a shell-interpreted string | `execFile('echo', args, ...)` — fixed command, argument array, no shell |
| Hardcoded credential | `var password = "user123"` | `process.env.APP_PASSWORD` |
| Weak hashing | `sha1(password)` / `md5(password)` | `bcrypt.hashSync(password, 12)` |
| DOM XSS | `document.write("Hello, " + user.name)` | `el.textContent = "Hello, " + name` |
| Synchronous XHR | `xhr.open("GET", url, false)` | `fetch(url)` (async) |
| IDOR | `getUserProfile(userId)` — no auth check | requires `requestingUser.canAccess(userId)`, throws otherwise |
| SQL injection | string-concatenated `WHERE id = " + userId` | parameterized `WHERE id = ?`, `[userId]` |
| Reflected XSS | `document.write(userInput)` | `el.textContent = userInput` |

`multiple.js` is refactored to `module.exports` the testable functions, and
guards all browser-only calls (`document`, `window`) behind a
`typeof window !== 'undefined'` check so `require('./multiple')` is safe
under Jest/Node. **This file is not referenced by `index.html`** — it is a
standalone SAST-scan/demo target, not part of the shipped game bundle, so
this refactor cannot affect actual gameplay.

## 5. Kubernetes Resources

`k8s/deployment.yaml` (rendered version, on `deploy` branch, tag varies):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: supermariogame-deployment
spec:
  replicas: 1
  selector:
    matchLabels: {app: supermariogame}
  template:
    metadata:
      labels: {app: supermariogame}
    spec:
      containers:
      - name: supermariogame-container
        image: <dockerhub-username>/supermariogitopsproject:<short-sha>
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata:
  name: supermariogame-service
spec:
  selector: {app: supermariogame}
  ports: [{protocol: TCP, port: 8600, targetPort: 8080}]
  type: LoadBalancer
```

No `Ingress`, no `HPA`, no `PodDisruptionBudget`, `replicas: 1` — this is a
POC, not a production topology. See HLD §6 for explicit out-of-scope items.

## 6. Open Items / Known Gaps

- Trivy `exit-code: '0'` means the pipeline never actually blocks on CVEs —
  intentional for now, flag if you want a hard gate.
- Container runs as Tomcat's default user inside the image (not explicitly
  dropped to non-root) — harden via a `USER` directive change and
  re-verify Tomcat's `webapps/ROOT` permissions if required by your
  security policy.
- No image pull secret / private registry — Docker Hub image is public.
- SonarQube project-wide `line_coverage` gate condition will likely stay
  red unless you either add broader test coverage or relax that specific
  condition (see §3.1 caveat).
