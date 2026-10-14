# Project history

Running log of what exists and what changed. **Add an entry at the top of "Change log" whenever code or a
process changes** (what, why, how it was verified). Do not put hostnames, tokens, account names or emails here:
this file is pushed to a public repository.

## What exists (state as of 2026-10-13)

Goal of the R&D: use SonarQube as a security / quality gate in a DevSecOps flow (local commit + Jenkins CI),
ahead of a GCP serverless deploy.

| Area | What | Where |
|---|---|---|
| App | Spring Boot 4.1.1, Java 21, sample `GradeService` + JUnit 5 tests | `src/` |
| Lint | Checkstyle, bound to Maven `validate`, so every build runs it | `pom.xml`, `config/checkstyle.xml` |
| Coverage | JaCoCo -> `target/site/jacoco/jacoco.xml`, read by Sonar | `pom.xml` |
| Local scan | lint + tests + coverage + Sonar scan + wait for gate, one command | `scan.sh` |
| Commit gate | git `pre-commit` runs `scan.sh`; docs-only commits skip it | `.githooks/pre-commit` |
| Dev env | devbox: JDK 21, git, curl, helper scripts | `devbox.json` |
| CI | parameterized Jenkins pipeline template | `Jenkinsfile` |
| Jenkins image | Jenkins LTS (JDK 21) + plugins + Configuration as Code + compose | `jenkins/` |
| Failure demos | bad classes as `.txt` so they are not compiled | `demo/bad-examples/` |

SonarQube side (not in the repo): Community Build, custom quality gate `rnd-strict` assigned to the project:
fails on any bug or vulnerability, > 10 code smells, coverage < 80%, duplication > 3%, or a security /
reliability / maintainability rating worse than A. It uses overall-code conditions because the default gate's
new-code conditions pass on the very first analysis.

Settings are variables, not constants: `SONAR_URL`, `SONAR_TOKEN`, `SONAR_PROJECT_KEY`, `SONAR_PROJECT_NAME`
in a git-ignored `.env` (template: `.env.example`).

## Decisions

- **One Sonar analysis per project.** Community Build has no branch analysis. Jenkins therefore scans only
  `SCAN_BRANCHES` (default `main,master`); other branches still run test, lint and build.
- **No Docker agent, no webhook in Jenkins.** The pipeline is Java/Maven only, so it runs on the controller with
  the image's JDK 21 and `./mvnw`. The gate is awaited with `-Dsonar.qualitygate.wait=true` (polling), because a
  Jenkins on a laptop is not reachable by the SonarQube server's webhook and the stage would hang.
- **Sonar token never on a command line in Jenkins**: the scanner reads env `SONAR_TOKEN`, injected from the
  `sonar-token` credential.
- **Template = parameters.** `REPO_URL`, `BRANCH`, `SONAR_PROJECT_KEY`, `SONAR_PROJECT_NAME` select the
  project; the target repo needs Maven wrapper + Checkstyle + JaCoCo like this one.
- **Sensitive data stays out of the public repo.** The SonarQube host, project keys, admin-account details
  and work email are not committed: they are variables (`$SONAR_URL`, `$SONAR_PROJECT_KEY`, `$SONAR_TOKEN`)
  whose values live in the git-ignored `.env`. `SONAR-RESEARCH.md` is pushed in sanitized form. Commit author
  is the GitHub noreply address. Local secret files (`.env`, `config.env`, the old token file) are git-ignored.

## Change log

### 2026-10-14 - own quality gate in the pipeline, no DB password, readable Jenkinsfile
- **Feedback 1, database password:** the pipeline no longer asks for it. `scripts/deploy.sh` reads
  `POSTGRES_USER` / `POSTGRES_PASSWORD` from the running database container (host name of `DB_URL`). Parameters
  `DB_USER` and `DB_PASSWORD_INPUT` and the JCasC credential `db-password` were removed; a global env
  `DB_PASSWORD` or a credential `db-password` is still honoured for a database that is not a local container.
  Prerequisites checks that the container exposes the login instead of failing on a missing secret.
- **Feedback 2, readability:** the Jenkinsfile went from ~480 to ~290 lines. The long shell blocks moved to
  `scripts/prerequisites.sh`, `scripts/sonar-scan.sh` and `scripts/sonar-gate.sh` (runnable and testable by
  hand); the Jenkinsfile only says what happens and in which order. Because the scripts live in the repo, a repo
  that reuses the Jenkinsfile must carry `scripts/` too.
- **Feedback 3, which gate does the scan use? Found by querying the server:** project `sonarqube` was on the
  default *Sonar way*, `rnd-strict` existed but was not assigned. Nothing in the pipeline chose a gate. Now
  parameter `SONAR_QUALITY_GATE` (default `rnd-strict`) is assigned before the scan by `scripts/sonar-gate.sh`,
  which also creates the project when missing and creates the gate with the strict conditions when the server does
  not have it (an existing gate is never modified). Tested against the real server with a temporary project and
  gate, both deleted afterwards. `scan.sh` does the same when `SONAR_QUALITY_GATE` is set in `.env`.
- **Question, dashboard name:** the name shown was `sonarcube` for all projects (checked on the server) because
  `sonar.projectName` was only sent when `SONAR_PROJECT_NAME` was filled; otherwise the Maven plugin uses `<name>`
  of `pom.xml`. The parameter text claimed "empty = the key", which was wrong. Now the name defaults to the key in
  the pipeline and in `scan.sh`.
- Verified: in a probe job `env.STAGE_NAME` in the final `post` block is "Declarative: Post Actions", so each stage
  keeps `post { failure { markFailed() } }`.

### 2026-10-13 - presentation of the R&D
- `.project/SonarQube-RnD.pptx`: 10-slide deck (Indonesian, ~15 min, mixed Dev/QA/Lead audience) with speaker
  notes: what SonarQube is, how it works, quality gate (`rnd-strict` vs the default gate), the R&D setup, 6 setup
  steps, the Jenkins pipeline, SonarQube features per development stage (used / available / paid edition),
  findings and limits. No host, token or project names. Built with pptxgenjs; layout checked by rendering in
  PowerPoint. Not committed (binary); the source script is not kept in the repo.

### 2026-10-13 - end-to-end: endpoint + Postgres + image + deploy (branch `rnd`)
- **App:** `GET /api/students` (controller -> service -> `JdbcClient` repository) reads the `students` table and
  adds the letter grade from `GradeService`. Deps: `spring-boot-starter-webmvc`, `-jdbc`, `postgresql` (runtime),
  `h2` (test). Config from env: `DB_URL`, `DB_USER`, `DB_PASSWORD` (no default on purpose).
- **Tests:** 7 tests, no database needed. H2 in memory loads the same `db/init.sql` that Postgres runs; one test
  goes through the whole stack with `MockMvc` + the real context. Lint 0 violations.
- **Database = separate infrastructure** (`docker-compose.yml`, container `sonarcube-db`, network
  `sonarcube-net`, named volume). The pipeline never starts it: it mirrors a real project where the pipeline only
  ships the application. Started with `devbox run db-up`; needs `DB_PASSWORD` in `.env`.
- **Runtime image:** `Dockerfile` (temurin 21 JRE alpine, non-root) copies the jar the pipeline built.
- **Jenkinsfile** reworked: Checkout -> Prerequisites -> Test -> Lint -> SonarQube scan -> Build -> Image ->
  Deploy -> Smoke test. Deploy/Image/Smoke run only when `DEPLOY` is on and the branch was scanned. Java version is
  read from `pom.xml` (the `REQUIRED_JAVA` parameter is gone). New parameters: `DEPLOY`, `IMAGE_NAME`,
  `APP_PORT`, `DB_URL`, `DB_USER`, `DB_PASSWORD_INPUT`, `DOCKER_NETWORK`; DB password sources mirror the Sonar
  token (parameter, global env, credential `db-password`). `SCAN_BRANCHES` default now includes `rnd`.
- **`scripts/deploy.sh`:** stops the running container, starts the new tag with a healthcheck, waits, and on
  failure restores the previous image with the settings of the previous container (a first version used the new
  deploy's settings for the rollback; found by testing a deploy with a wrong password).
- `Jenkinsfile`: Checkout trims `REPO_URL` and `BRANCH`. A user's job failed with `fatal: protocol ' https' is not
  supported`: a leading space in a pasted URL (not an HTTPS problem; no reverse proxy is needed to clone).
- Pushed to `origin/rnd` with `--no-verify` at the user's request: the Sonar host was not reachable from the
  network in use, so the pre-commit gate could not run. Lint and the 7 tests had passed locally just before; the
  Sonar gate runs in the Jenkins build.
- **Restructured for learners (`startup/`).** The repo is a SonarQube learning project, so the environment is one
  command: `startup/docker-compose.yml` brings up Postgres and Jenkins; `startup/jenkins/` is the Jenkins image
  (docker CLI static binary, `/usr/lib/jvm/java-21-openjdk` link, plugins, JCasC). Jenkins uses the host docker
  through the mounted `docker.sock` (runs as root; local learning only). The app `Dockerfile` stays at the root.
  Jenkins login, DB password and the `db-password` credential are hardcoded in the compose file on purpose;
  `SONAR_URL` and `SONAR_TOKEN` are not (company data in a public repo) and come from the git-ignored `.env`.
  The old `jenkins/docker-compose.yml` and the root `docker-compose.yml` were merged into it. devbox scripts:
  `startup`, `startup-down`, `db-up`, `jenkins-logs`.
- **Verified in the containerised Jenkins (2026-10-13):** `startup` up -> job `sonar-pipeline` from branch `rnd`
  reached Prerequisites with both credentials found, docker working and the DB container detected (it stopped only
  because the Sonar host was not reachable from that network). A throw-away copy of the Jenkinsfile that does not
  require the scan then ran green: Checkout, Prerequisites, 7 tests, Lint 0, Build, Image, Deploy, Smoke test;
  a second run replaced the running container. The test job was deleted afterwards. The Sonar scan stage and the
  gate from inside this Jenkins are still unverified (network).
- **Verified locally with docker (2026-10-13):** DB up -> image build -> deploy -> smoke test -> `curl` on the host
  returned the 4 students with grades; redeploy while running replaced the container; a deploy with a wrong DB
  password failed with the cause quoted and rolled back to the previous version, which kept serving 200.
  Test containers and volume were removed afterwards.

### 2026-10-13 - failure reporting, smaller devbox
- `Jenkinsfile`: Java now comes from the `environment` block (`JAVA_HOME = "/usr/lib/jvm/java-21-openjdk"`,
  `PATH = "${env.JAVA_HOME}/bin:${env.PATH}"`), as asked; the `JDK_HOME` parameter is removed. The path must exist
  on the server (Prerequisites fails with the fix if it does not). `jenkins/Dockerfile` links
  `/usr/lib/jvm/java-21-openjdk` to the image's JDK so the same Jenkinsfile runs in the local container.
- **Jenkins tested for real** in a local container built from `jenkins/` (Docker; job `sonar-pipeline` seeded by
  JCasC, plus a throwaway `local-test` job that runs the working-tree Jenkinsfile without a push). Findings:
  - first build, parameters not registered yet: `params.X` has the defaults but `sh` gets no `REPO_URL` / `BRANCH`
    env vars, so the repo check failed. Prerequisites now passes them explicitly with `withEnv`.
  - the compose file passed `SONAR_TOKEN` into the container, which Jenkins reads as a global env var and skips the
    masked credential. It is now `JCASC_SONAR_TOKEN` (compose) and casc.yaml builds credential `sonar-token` from it.
    The compose file also no longer forwards the whole `.env` (so `TOKEN_GIT` stays out of the container).
  - with the scan skipped (`SCAN_BRANCHES=none`) the full run was green: Prerequisites, Checkout, Test (3 tests),
    Lint (0 violations), Build + archive. A token typed as `SONAR_TOKEN_INPUT` was masked and absent from the log.
- `Jenkinsfile`: bug found on the first real run of the Prerequisites stage: `params.SONAR_TOKEN_INPUT?.trim()`
  threw `No signature of method: hudson.util.Secret.trim()`, because password parameters are `Secret` objects,
  not Strings. All checks of that parameter now go through `isSet()` (`toString()` first). The failure hint also
  says to read the exception when there is no `[FAIL]` line.
- **Git credentials scoped to this project.** `scripts/git-credential-env` is a git credential helper that reads
  `TOKEN_GIT` (and optional `GIT_USERNAME`) from the git-ignored `.env` and answers only for `github.com`.
  Enabled with repo-local `credential.https://github.com.helper` (devbox `init_hook` does it), so no password
  prompt and no token in `.git/config`. Global git config is untouched.
- `Jenkinsfile`: removed the failure mail (`NOTIFY_EMAIL`) and chat webhook. A failed build now ends with a
  block in the console log that names the failed stage, a one-line reason, and for the Sonar stage the red
  quality gate conditions (metric, actual value, limit) read from `api/qualitygates/project_status`. The stage
  name is also written to the build description. Removed `mailer` from `jenkins/plugins.txt`, `CHAT_WEBHOOK_URL`
  from `jenkins/casc.yaml` and `.env.example`. Not run on a real Jenkins yet.
- `Jenkinsfile`: new first stage **Prerequisites**. Prints all build parameters with token/password values masked
  (name contains TOKEN, PASSWORD or SECRET), the effective `SONAR_URL`, `JAVA_HOME`, node and token source, then
  checks tools, Java/`javac` against the new `REQUIRED_JAVA` parameter, repo and branch with `git ls-remote`,
  Maven Central (warning only), and for scanned branches SonarQube status plus token validity
  (`api/authentication/validate`). Failures are `[FAIL]` lines and copied to `.pipeline.log` so the failure block
  quotes them. The script was tested locally in four scenarios (all good, no token, no Java, bad branch).
- `Jenkinsfile`: second Jenkins run passed the Java check but still failed in Test, and the log excerpt did not
  show the Maven error. Maven output is now also appended to `.pipeline.log` (helper `mvn()`), and the
  "WHY THIS BUILD FAILED" block quotes the first 15 `[ERROR]` lines. The Java check also verifies that `javac`
  exists (a JRE-only install reports a valid `java -version`).
- `Jenkinsfile`: first real Jenkins run failed with `release version 21 not supported` (node had an older JDK).
  Added a Java check at the start of the Test stage (reads `<java.version>` from `pom.xml`, fails with the fix
  in the message) and a `JDK_HOME` parameter that sets `JAVA_HOME` for the build, so no admin rights are needed.
  The check script was tested locally with JDK 21, a fake JDK 17 and no Java.
- `Jenkinsfile`: the Sonar token no longer requires the `sonar-token` credential. It is taken from parameter
  `SONAR_TOKEN_INPUT` (password type), else global env var `SONAR_TOKEN`, else the credential. Added for Jenkins
  users who cannot create credentials. Not run on a real Jenkins yet.
- `Jenkinsfile`: removed `timestamps()` and the `junit` publisher, so only Pipeline, Git and Credentials
  Binding are required. Unit tests are unchanged: Spring Boot tests (`spring-boot-starter-test`, JUnit 5) run by
  Maven Surefire in the Test stage; failures show in the console log instead of a Jenkins test report. Removed
  `timestamper` and `junit` from `jenkins/plugins.txt`.
- `devbox.json`: packages reduced to `jdk@21`; `devbox.lock` committed. `git` was only used through the host (the hook and init_hook run
  `git`, and the repo is cloned with it), and `curl` is not needed because `mvnw` falls back to a Java
  downloader. `devbox shell --pure` would hide the host `git`; use plain `devbox shell`.

### 2026-10-12 - hardening, Jenkins template, publish prep
- **Fixed: commit hook never ran on this machine.** `.githooks/pre-commit`, `scan.sh` and `mvnw` were mode 644 on
  disk (index had 755, but `core.fileMode=false` hid it), so git ignored the hook. Restored `+x` and set
  `core.fileMode=true` for the repo. Verified with the failure and skip paths below.
- `scan.sh`: removed hardcoded server URL and project key; `SONAR_URL` and `SONAR_PROJECT_KEY` are now required
  variables, `SONAR_PROJECT_NAME` optional. When no JDK is on PATH it re-runs itself through `devbox run`.
- `.githooks/pre-commit`: `scan.sh` changes now trigger the full gate.
- `Jenkinsfile`: rewritten as a parameterized template. Stages: Checkout (REPO_URL @ BRANCH) -> Test -> Lint ->
  SonarQube scan + gate -> Build (jar archived). Replaced the Docker agent and `waitForQualityGate` webhook with
  controller execution and `sonar.qualitygate.wait`. (Mail and chat were removed again on 2026-10-13.)
- `jenkins/`: new `plugins.txt` and `casc.yaml` (admin user, `sonar-token` credential, `SONAR_URL`, seeded
  `sonar-pipeline` job); Dockerfile no longer installs the docker CLI; compose binds `127.0.0.1:8080`, reads
  `.env` and refuses to start without admin password, URL and token.
- `scan.sh`: strips `\r` when loading `.env`. A `.env` saved with Windows line endings made the scanner fail
  with `Malformed URL`; found during the first real run.
- **History rewritten, remote must be force-pushed.** The original commit (host, work email, research notes)
  had already reached the public `origin/main`. It was replaced locally by one clean root commit (author =
  GitHub noreply address, repo-local `user.email`). The old commit is kept only on the local branch
  `backup/pre-sanitize`, which must never be pushed. Publishing needs
  `git push --force-with-lease=main:<old-sha> origin main`; GitHub may keep serving the old SHA for a while.
- `devbox.json`: scripts `jenkins-up`, `jenkins-logs`, `jenkins-down`.
- `.gitignore`: `!.project/` (the Eclipse `.project` rule would have ignored this folder), `config.env`,
  `*.local.env`. A token file named `config.env` was found untracked and not ignored: renamed to `.env`.
- `SONAR-RESEARCH.md` sanitized: host, project keys, token file name and account roles replaced by variables
  or generic wording. Pushed with the repo.
- README scrubbed of the company host and project key; Jenkins section rewritten.
- Review of `devbox.json`: packages `jdk@21`, `git`, `curl` resolve on the devbox registry (JDK 21.0.9).
  Missing `devbox.lock`, so versions are not pinned yet.

### 2026-10-07 - initial build (earlier session)
- Spring Boot sample, Checkstyle + JaCoCo, `scan.sh`, pre-commit hook, devbox, first Jenkinsfile and Jenkins
  Dockerfile, demo bad examples, quality gate `rnd-strict`, first scans (see "What exists").

## Verification status

| Check | Status | How |
|---|---|---|
| `scan.sh` fails fast on missing URL / key / token | verified 2026-10-12 | ran with cleared env |
| `scan.sh` hands over to `devbox run` without a JDK | verified with a stub `devbox` | no real devbox run |
| `scan.sh` tolerates CRLF `.env` | verified | the real failure it fixes was reproduced first |
| Hook passes on clean code (lint, 3 tests, Sonar gate PASSED) | **verified** 2026-10-12 | real commit through the hook, temporary Temurin JDK 21 |
| Hook rejects bad code | **verified** | `demo/bad-examples/LegacyUtil.java.txt` rejected at lint (2 violations) |
| Hook skips docs-only commits | verified | |
| `casc.yaml`, `docker-compose.yml`, `devbox.json` parse | verified | YAML / JSON parser |
| `devbox shell`, hook through devbox (no JDK on PATH) | **verified** 2026-10-13 | Nix JDK 21.0.12.1; commit gated by lint, 3 tests, Sonar gate PASSED |
| Jenkins image build, boot, JCasC job + credential | **verified** 2026-10-13 | local Docker container |
| Pipeline without scan (Prerequisites, Checkout, Test, Lint, Build) | **verified** 2026-10-13 | local Jenkins, `SCAN_BRANCHES=none` |
| Pipeline with Sonar scan and gate from Jenkins | **pending** | needs a network that can reach the Sonar host |
| Image, Deploy, Smoke test in the `startup` Jenkins | **verified** 2026-10-13 | test copy of the Jenkinsfile without the scan requirement |

## Open items

- Add the dev user to the `docker` group and run `devbox run jenkins-up` to verify the Jenkins image.
- Pin Jenkins plugin versions in `jenkins/plugins.txt` once the image is known to work.
- Java package and Maven groupId still contain the company name (`com.altama`).
- Rotate the admin token used during the research and use a scoped user token for Jenkins.
- Deploy stage (`gcloud run deploy`) once a GCP project is chosen.
