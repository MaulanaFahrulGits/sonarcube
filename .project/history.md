# Project history

Running log of what exists and what changed. **Add an entry at the top of "Change log" whenever code or a
process changes** (what, why, how it was verified). Do not put hostnames, tokens, account names or emails here:
this file is pushed to a public repository.

## What exists (state as of 2026-10-12)

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

### 2026-10-12 - hardening, Jenkins template, publish prep
- **Fixed: commit hook never ran on this machine.** `.githooks/pre-commit`, `scan.sh` and `mvnw` were mode 644 on
  disk (index had 755, but `core.fileMode=false` hid it), so git ignored the hook. Restored `+x` and set
  `core.fileMode=true` for the repo. Verified with the failure and skip paths below.
- `scan.sh`: removed hardcoded server URL and project key; `SONAR_URL` and `SONAR_PROJECT_KEY` are now required
  variables, `SONAR_PROJECT_NAME` optional. When no JDK is on PATH it re-runs itself through `devbox run`.
- `.githooks/pre-commit`: `scan.sh` changes now trigger the full gate.
- `Jenkinsfile`: rewritten as a parameterized template. Stages: Checkout (REPO_URL @ BRANCH) -> Test -> Lint ->
  SonarQube scan + gate -> Build (jar archived). Replaced the Docker agent and `waitForQualityGate` webhook with
  controller execution and `sonar.qualitygate.wait`. Mail and chat notification are optional.
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
| `devbox shell` / `devbox run build` | **pending** | Nix not installed in this WSL distro; its installer needs `sudo` in a terminal |
| Jenkins image build, boot, JCasC job, full pipeline | **pending** | Docker socket not accessible to the dev user (docker group) |

## Open items

- Install Nix (`devbox shell` once, needs sudo), then commit `devbox.lock` (reproducible versions).
- Add the dev user to the `docker` group and run `devbox run jenkins-up` to verify the Jenkins image.
- Pin Jenkins plugin versions in `jenkins/plugins.txt` once the image is known to work.
- Java package and Maven groupId still contain the company name (`com.altama`).
- Rotate the admin token used during the research and use a scoped user token for Jenkins.
- Deploy stage (`gcloud run deploy`) once a GCP project is chosen.
