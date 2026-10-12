# SonarQube R&D: Jenkins + Docker, for GCP serverless (Java)

> Sanitized for the public repo: server URL, project keys and credentials are variables
> (`$SONAR_URL`, `$SONAR_PROJECT_KEY`, `$SONAR_TOKEN`, values live in the git-ignored `.env`).

Researched 2026-10-07. Target: **SonarQube Community Build** (user's existing server), Java 21 / Spring Boot 4.1.1 sample in this repo.
Items marked **[verify]** come from docs I could not fully open or from memory. Check them against your server's own `/web_api` page.

## 0. What was built here (and what was not run)

| File | Purpose | Status |
|---|---|---|
| `pom.xml` (+JaCoCo) | Produces `target/site/jacoco/jacoco.xml`, which Sonar reads for coverage | `mvnw verify` ran OK locally |
| `src/.../DemoService.java`, `LegacyUtil.java` + test | Deliberate bugs, vulnerabilities, smells and low coverage for the scan to find | scanned, see §10 |
| `scan.sh` | Local build + test + scan, exits 1 when the gate fails | run against `$SONAR_URL` |
| `Jenkinsfile` | build, scan, wait for quality gate, notify on failure | **not run** (no Docker or Jenkins on this PC) |
| `jenkins/Dockerfile`, `docker-compose.yml` | New Jenkins with docker CLI and the Sonar plugin | **not run** |

## 1. What to prepare

1. **Sonar server**: URL reachable **from the Jenkins container** (not `localhost`). Check the edition and version at `GET /api/system/status` and `/api/server/version`.
2. **Admin token** (`squ_...`) for `scan.sh`. The account needs *Create Projects* (and *Administer Quality Gates* only if you create gates).
3. **Jenkins** (new, from `jenkins/`): a Docker host with `/var/run/docker.sock`, with port 8080 reachable by Sonar. The webhook goes Sonar → Jenkins, so firewall direction matters.
4. **Jenkins config**: plugin *SonarQube Scanner*. Under *Manage Jenkins → System → SonarQube servers*, add name `sonar`, the URL, and a *Secret text* credential holding the token.
5. **Notification channel**: SMTP details (host, port, user, password) and/or a Slack or Google Chat incoming-webhook URL.
6. **A Git repo** for Jenkins to clone (to be decided). Until then, the Jenkinsfile can run from a pasted script.
7. **GCP side** (later): a service account for `gcloud run deploy` / `gcloud functions deploy`, stored in Jenkins credentials.

## 2. Ways to create a project in SonarQube (Goal 1)

| # | Method | How | Good for | Limits |
|---|---|---|---|---|
| 1 | **Local project (UI)** | Projects → Create Project → *Local project* → name, key, new-code definition | First try, one-offs | Manual, so it doesn't scale |
| 2 | **Import from DevOps platform** | Create Project → GitHub / GitLab / Bitbucket / Azure DevOps. Needs the platform configured by an admin and a PAT | Repos already on a platform | Per the docs it is available in Community Build **[verify the menu in your UI]**. Branch and PR decoration are **not** (see §6) |
| 3 | **Web API** | `POST /api/projects/create` (name, project key). For bound projects: `api/alm_settings/create_<platform>`, `api/alm_integrations/set_pat`, `POST api/v2/dop-translation/bound-projects` | Many projects, repeatable, IaC-style | Needs a token with *Create Projects* |
| 4 | **First scan auto-creates it** | Run the scanner with `-Dsonar.projectKey=...` and a token with *Create Projects* | Fastest from Jenkins (zero setup) | The project gets the **default** gate, profile and visibility until you change them. Use a global token, not a project-scoped one |
| 5 | Terraform (optional) | Community provider `jdamata/sonarqube` | Many instances | Third-party, not researched further |

**Recommendation:** use #4 for the first experiment and #3 for anything real. #3 creates the project with the right gate before the first scan.
Permission template: the *Create Projects* permission applies to every method, and the creator becomes project admin.

## 3. Jenkins + Docker pipeline (Goal 2)

See `Jenkinsfile`. How it works:

```
Jenkins (container) ─docker.sock─> sibling container maven:3.9-eclipse-temurin-21
  mvn verify (tests + JaCoCo)
  withSonarQubeEnv('sonar') { mvn ...sonar-maven-plugin:sonar }   -> uploads the analysis
  waitForQualityGate abortPipeline:true                            -> blocks until Sonar's webhook calls back
```

- `withSonarQubeEnv` injects the server URL and token and records the analysis task id.
- `waitForQualityGate` pauses the pipeline until SonarQube POSTs to `http://<jenkins>:8080/sonarqube-webhook/`. **Without this webhook the stage hangs until the timeout.** It is the most common failure. The webhook payload can be signed with HMAC-SHA256. Set a secret and use `waitForQualityGate(webhookSecretId: '...')`.
- Alternative without the Jenkins plugin: `sonarsource/sonar-scanner-cli` image with `-Dsonar.qualitygate.wait=true`. It polls instead of using a webhook, which is simpler but gives you no Jenkins badge or widget.
- Docker-in-Jenkins gotcha: because Jenkins is itself a container, workspace volume mapping between it and `agent { docker }` containers can break. docker-workflow normally handles it with `--volumes-from`. If a stage fails with an empty workspace, bind-mount `jenkins_home` at the same path on the host.
- Maven agent runs as root in the container and caches in the `maven-repo` volume.

## 4. What SonarQube can enforce (Goal 3)

**Yes. Quality gates fail the build on thresholds you set.** Each condition applies to **new code** or to **overall code**. Built-in gates focus on new code.

*Sonar way* (default, read-only): no new issues · all new security hotspots reviewed · new-code coverage ≥ 80% · new-code duplication ≤ 3%.
You can **copy it or create a custom gate** (needs *Administer Quality Gates*), then assign it per project or set it as the default.
Fudge factor: coverage and duplication conditions are ignored until the change has ≥ 20 new lines.

Mapping your "percentage" idea to real metrics:

| You want | Metric key | Condition example |
|---|---|---|
| No new vulnerabilities | `new_vulnerabilities`, or rating `new_security_rating` | rating worse than A, or count > 0 |
| No new bugs | `new_bugs`, `new_reliability_rating` | same pattern |
| Code smell **count** | `new_code_smells` | > N |
| Code smell **percentage** | `new_sqale_debt_ratio` (technical debt ÷ development cost), which drives `new_maintainability_rating` | A ≤ 5%, B ≤ 10%, C ≤ 20%, D ≤ 50% |
| Coverage % | `new_coverage` / `coverage` | < 80 |
| Duplication % | `new_duplicated_lines_density` | > 3 |
| Complexity | `complexity`, `cognitive_complexity` | > N |
| Hotspots | `new_security_hotspots_reviewed` | < 100% |

Sonar has no plain "N% of lines are smells" metric. Debt ratio is the percentage form.
Ratings: A=1 … E=5, so "GT 1" means worse than A. Rules for *what counts as an issue* live in **Quality Profiles** (copy *Sonar way* for Java, then activate or deactivate rules). The gate then judges the results.
All of these can be set in the UI (Quality Gates → Create → Add Condition) or via the API (`api/qualitygates/create`, `create_condition`, `select`). **[verify]** the `op` parameter on your version, since newer versions fix the direction per metric.
Read the gate result from the API: `GET /api/qualitygates/project_status?projectKey=...`.

## 5. Notify on failure (Goal 4)

Yes, in four ways. Pick by who needs to know:

| Option | Where it's configured | Trigger | Notes |
|---|---|---|---|
| **A. Jenkins `post { failure }`** | `Jenkinsfile` (`mail` and a `curl` to a chat webhook) | Build failed, including a gate failure, since `abortPipeline` fails the build | Needs SMTP in Jenkins or a webhook URL. **Recommended** |
| **B. SonarQube email** | Administration → General → *Email* (SMTP, base URL) and each user's *My Account → Notifications* | Per-project events such as a quality gate status change **[verify exact wording]** | Each user subscribes themselves, because you can't subscribe someone else. Fires on the Sonar side even when Jenkins isn't involved |
| **C. Sonar webhook → your endpoint** | Administration → Webhooks (max 10 global + 10 per project) | Every analysis completion, payload includes `qualityGate.status` | 10 s timeout, no retry. Good fit: a small **Cloud Function** that relays to Google Chat or Slack |
| **D. Jenkins plugins** | Slack, Email-ext, Google Chat plugins | Same as A | More features, more plugins to maintain |

Chat payload `{"text": "..."}` works for both Slack and Google Chat incoming webhooks. Microsoft Teams needs its Workflows webhook, since the old connectors are being retired **[verify]**.

## 6. Community Build limits that affect the design

- **No branch analysis and no PR analysis.** Only one branch (main) is analyzed. This means no PR decoration or inline PR comments, and a feature-branch pipeline would overwrite main's analysis. Run Sonar only on `main` / release builds, or upgrade to Developer Edition. The community-built `sonarqube-community-branch-plugin` exists but is third-party and tied to specific versions. Not recommended for anything serious.
- Quality gates, quality profiles, webhooks, notifications, API, 21 languages (Java included): **all available**.
- **Tested on server 26.9: the first analysis of a project computes no new-code values, so *Sonar way* (all four conditions are new-code) PASSES the very first scan even with bugs and vulnerabilities in the code.** It only starts judging from the second analysis, and only on code changed since the baseline (default New Code Definition: previous version). To fail from scan #1, use a gate with **overall-code** conditions (`bugs`, `vulnerabilities`, `coverage`, ratings), like `rnd-strict` in §10.
- A new custom gate is created pre-filled with the four *Sonar way* conditions, and you can't add a duplicate of one of them.

## 7. GCP serverless: where Sonar fits

Sonar scans **source code**, not images or deployed functions. So it always sits in CI *before* deploy. A container-image scan is a different tool (Artifact Registry vulnerability scanning, Trivy).

| Deploy mode | Where Sonar hooks in | Gate enforcement |
|---|---|---|
| **Image import** (Cloud Run from Artifact Registry) | Jenkins: scan source → `docker build` → push → `gcloud run deploy --image` | Deploy stage runs only if the quality gate passed. The image alone has no source to scan |
| **Git connection** (Cloud Run / Functions continuous deploy, Cloud Build trigger on GitHub) | Jenkins scans the same commit | **Race risk**: the Cloud Build trigger deploys on push regardless of Jenkins. Options: Jenkins performs the deploy, or the trigger watches a `release` branch that Jenkins updates only after a green gate |
| **Function by name / source deploy** (`gcloud functions deploy NAME --source .`) | Jenkins stage: scan, wait for gate, then the deploy command | Same as image import: the deploy stage is last |

Java notes: Cloud Run functions (Java) and Cloud Run both build from Maven, so the same `mvn verify` + sonar-maven-plugin works unchanged.

## 8. Suggested R&D order

1. `docker compose -f jenkins/docker-compose.yml up -d --build`, then unlock Jenkins and add the `sonar` server + credentials.
2. In the UI: generate a user token, add the Jenkins webhook, and create a custom gate set as default. Let the first scan create the project (method 4).
3. Create a pipeline job from the `Jenkinsfile` with the `rnd-strict` gate on the project. The build should **fail the gate** and send the notification.
4. Fix `DemoService` and `LegacyUtil` (hard-coded passwords, `==` on strings, MD5, unclosed reader, and so on, then add tests) and re-run for green.
5. Add the Deploy stage with `gcloud` once a repo and GCP project are chosen.

## 9. Open questions for next round

- Git hosting (GitHub / GitLab / Bitbucket / GitBucket?), and does Jenkins reach it from the server's network?
- Which chat or email channel is final?
- Do you need PR or branch gating? If yes, Community Build is the wrong edition, so confirm the upgrade budget.
- Single repo or multiple services? That decides one project per repo and a shared custom gate, versus per-service gates.

## 10. Local scan results (2026-10-07, `$SONAR_URL`, SonarQube Community Build 26.9)

Run with `scan.sh` from this PC. The token (an admin account) came from the git-ignored `.env`.

| Project | How created | Gate | Result |
|---|---|---|---|
| `$MANUAL_PROJECT_KEY` | Already created by hand in the UI, scan only | Sonar way (default) | **PASSED**, even though the scan found 24 issues (3 bugs, 2 vulnerabilities, 19 smells, 7.3% coverage). Reason: all Sonar way conditions are new-code and nothing is "new" on analysis #1 |
| `$SONAR_PROJECT_KEY` scan #1 | **Auto-created by the first scan** (needed no manual step) | Sonar way (default, assigned automatically) | PASSED, same reason |
| `$SONAR_PROJECT_KEY` scan #2 | Gate switched to `rnd-strict` via `api/qualitygates/select`, then rescanned | `rnd-strict` | **FAILED**, `scan.sh` exited 1, Maven reported BUILD FAILURE |

`rnd-strict` (created through the API, **not** made the server default, because the server is shared). Conditions on overall code, which are evaluated from the first scan:

| Condition | Threshold | Actual | Result |
|---|---|---|---|
| `vulnerabilities` | > 0 | 2 | error |
| `bugs` | > 0 | 3 | error |
| `code_smells` | > 10 | 19 | error |
| `coverage` | < 80% | 7.3% | error |
| `security_rating` | worse than A | 4 (D) | error |
| `reliability_rating` | worse than A | 5 (E) | error |
| `sqale_rating` (maintainability) | worse than A | 1 (A) | ok |
| `duplicated_lines_density` | > 3% | 0.0% | ok |
| plus the 4 inherited new-code conditions | | none evaluated | ok |

Takeaways:
- Auto-create works with a plain user token, and the new project silently takes the **default** gate. Setting `rnd-strict` as the server default would make every future first-scan project use it, but it would also change every other project on the server.
- The metric keys here come from the server's own `/api/metrics/search`. This version also has `software_quality_*` (MQR) variants of the issue metrics. The classic keys used above still work.
- The token sits in a plain text, git-ignored file in the project folder. It belongs to an admin account. Rotate it when the R&D is done, and use a scoped token for Jenkins.

## 11. What was done and how (reproducible log)

`$U` = `$SONAR_URL`, `$T` = `SONAR_TOKEN` from the git-ignored `.env`. The API calls use basic auth with the token as the username and an empty password (`curl -u "$T:"`).

| # | Step | How |
|---|---|---|
| 1 | Research | Read the official SonarQube Community Build docs (project creation, quality gates, Jenkins integration, webhooks, notifications). Pages that returned 404 are marked **[verify]** in this file |
| 2 | Prepare the sample project | Found an existing Spring Boot 4.1.1 / Java 21 project in this folder. Added the JaCoCo plugin to `pom.xml` so `mvn verify` writes `target/site/jacoco/jacoco.xml`, which the scanner imports as coverage |
| 3 | Write the Jenkins parts | `Jenkinsfile` (Maven container → `withSonarQubeEnv` → `waitForQualityGate` → mail and chat on failure) and `jenkins/` (Dockerfile + compose). **Not run**, because this PC has no Docker |
| 4 | Write `scan.sh` | One command that runs `./mvnw verify org.sonarsource.scanner.maven:sonar-maven-plugin:sonar` with `-Dsonar.qualitygate.wait=true`. Reads `SONAR_URL`, `SONAR_TOKEN` and `SONAR_PROJECT_KEY` from the environment, so no secret is stored in the file |
| 5 | Check the server and token | `GET $U/api/system/status` (UP, 26.9), `GET /api/authentication/validate` (valid), `GET /api/users/current` (an administrator account with quality-gate, project-creation and analysis permissions). `GET /api/projects/search` showed that only `$MANUAL_PROJECT_KEY` existed |
| 6 | Plant flaws | Added `LegacyUtil.java` and extended `DemoService.java`. Checked `./mvnw verify` still passes. the token file was added to `.gitignore` |
| 7 | Manual project scan | Env vars set, then `SONAR_PROJECT_KEY=$MANUAL_PROJECT_KEY ./scan.sh`. Result PASSED |
| 8 | Investigate the unexpected pass | Compared `GET /api/qualitygates/project_status`, `/api/measures/component`, `/api/issues/search` and `/api/qualitygates/show?name=Sonar way`. Found 24 issues but `conditions: []`, which led to the first-analysis finding in §6 |
| 9 | Create the rules | `POST /api/qualitygates/create` (`name=rnd-strict`), then `POST /api/qualitygates/create_condition` once per row with `gateName`, `metric`, `op` (`GT` or `LT`) and `error`. Metric keys were taken from `GET /api/metrics/search`. Not set as default |
| 10 | Auto-create scan | `SONAR_PROJECT_KEY=$SONAR_PROJECT_KEY ./scan.sh`. The project didn't exist, and the scan created it with Sonar way (`GET /api/qualitygates/get_by_project`) |
| 11 | Apply the rules | `POST /api/qualitygates/select` with `gateName=rnd-strict&projectKey=$SONAR_PROJECT_KEY` (HTTP 204), then rescanned. The gate returned FAILED and `scan.sh` exited 1 |
| 12 | Read the verdict | `GET /api/qualitygates/project_status?projectKey=$SONAR_PROJECT_KEY` gave the per-condition actual vs threshold values shown in §10 |

To repeat steps 9 and 11 on another project, these are the only API calls needed:

```bash
api() { curl -sS -u "$T:" -X POST "$U/api/$1" "${@:2}"; }
api qualitygates/create           -d name=rnd-strict
api qualitygates/create_condition -d gateName=rnd-strict -d metric=bugs -d op=GT -d error=0
api qualitygates/select           -d gateName=rnd-strict -d projectKey=$SONAR_PROJECT_KEY
```

To re-run a scan and see the verdict:

```bash
SONAR_URL=$U SONAR_TOKEN=$T SONAR_PROJECT_KEY=$SONAR_PROJECT_KEY ./scan.sh   # exit code 1 = gate failed
```

What was **not** verified: the Jenkins pipeline, the webhook, and email and chat notifications (all need a running Jenkins), and the three GCP deploy modes (§7 is design only).

## Sources

- [Creating your project](https://docs.sonarsource.com/sonarqube-community-build/project-administration/creating-project)
- [Automating project creation](https://docs.sonarsource.com/sonarqube-community-build/project-administration/creating-project/automating-creation.md)
- [Jenkins pipeline pause](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/ci-integration/jenkins-integration/pipeline-pause)
- [Jenkins key features](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/ci-integration/jenkins-integration/key-features)
- [Quality gates](https://docs.sonarsource.com/sonarqube-community-build/quality-standards-administration/managing-quality-gates/introduction-to-quality-gates)
- [Webhooks](https://docs.sonarsource.com/sonarqube-community-build/project-administration/webhooks)
- [Notifications](https://docs.sonarsource.com/sonarqube-community-build/instance-administration/system-functions/notifications.md)
- [Community Build vs branches](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/analysis-overview)
