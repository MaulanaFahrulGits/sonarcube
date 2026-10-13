# sonarcube

Spring Boot (Java 21) sample used to explore SonarQube + Jenkins on GCP serverless.
Every commit is gated locally (lint, unit tests, SonarQube quality gate), and Jenkins runs the same checks.

- SonarQube: Community Build. Server URL, token and project key are variables in `.env` (see `.env.example`).
- Research notes and findings: [SONAR-RESEARCH.md](SONAR-RESEARCH.md)
- Change log of what exists and why: [.project/history.md](.project/history.md)

## Project structure

```
.
├── src/main/java/...        application code (GradeService is the sample logic)
├── src/test/java/...        JUnit 5 tests
├── config/checkstyle.xml    lint rules (Checkstyle)
├── .githooks/pre-commit     blocks the commit when lint, tests or the Sonar gate fail
├── scan.sh                  lint + test + coverage + Sonar scan, one command (used by the hook)
├── devbox.json              reproducible dev environment (JDK 21, git, curl) + helper scripts
├── .env.example             copy to .env: SONAR_URL, SONAR_TOKEN, SONAR_PROJECT_KEY, Jenkins admin
├── Jenkinsfile              CI template: checkout BRANCH, test, lint, Sonar scan + gate, build
├── jenkins/                 Dockerfile, plugins, Configuration-as-Code and compose for Jenkins
├── demo/bad-examples/       deliberately bad classes (.txt, not compiled) to trigger failures
├── SONAR-RESEARCH.md        research summary (sanitized: URL/keys are variables)
├── .project/history.md      running log of what was built and changed
└── pom.xml                  Maven: Checkstyle (validate phase), JaCoCo, Spring Boot
```

## Quick start with devbox (recommended)

Devbox installs the right JDK and tools for you. Nothing else is installed manually.

1. Install devbox: https://www.jetify.com/devbox/docs/installing_devbox/
   Linux and macOS work directly. **On Windows use WSL2** (devbox does not run in plain PowerShell).
2. Get your SonarQube URL, project key and a token: log in → avatar → **My Account → Security → Generate Tokens** → type **User Token**.
   Your account needs the *Create Projects* and *Execute Analysis* permissions.
3. In the repo:
   ```bash
   git clone https://github.com/MaulanaFahrulGits/sonarcube.git && cd sonarcube
   cp .env.example .env        # then edit .env: SONAR_URL, SONAR_PROJECT_KEY, SONAR_TOKEN
   devbox shell                # installs tools, enables the git hook automatically
   devbox run build            # lint + tests + coverage
   ```

| Command | What it does |
|---|---|
| `devbox run build` | `mvnw verify`: Checkstyle, tests, JaCoCo coverage |
| `devbox run test` | unit tests only |
| `devbox run lint` | Checkstyle only |
| `devbox run scan` | everything above, then the SonarQube scan and quality gate |
| `devbox run run` | start the app |
| `devbox run jenkins-up` / `jenkins-logs` / `jenkins-down` | manage the local Jenkins container |

## Without devbox

Needs JDK 21 and git. Maven is downloaded by the wrapper.

```bash
cp .env.example .env              # set SONAR_URL, SONAR_PROJECT_KEY, SONAR_TOKEN
git config core.hooksPath .githooks   # enable the commit hook (devbox does this for you)
./mvnw -B verify                  # build
./scan.sh                         # build + Sonar scan
```

On Windows, run the `.sh` files from Git Bash.

## Commit workflow

```
git commit
  └─ .githooks/pre-commit
       1. Checkstyle        (config/checkstyle.xml)
       2. Unit tests        (+ JaCoCo coverage)
       3. SonarQube scan    (waits for the quality gate)
     any step fails → commit is rejected, fix and commit again
```

- Commits that touch only docs (no `.java`, `.xml`, `.yml`, `.properties`, `Jenkinsfile`) skip the checks.
- The scan takes about a minute. Use `devbox run lint` or `devbox run test` for faster feedback while working.
- `git commit --no-verify` skips the hook. Jenkins runs the same checks, so the build will still fail.
- A missing `SONAR_URL`, `SONAR_PROJECT_KEY` or `SONAR_TOKEN` also blocks the commit, with a message telling you what to set.
- Outside `devbox shell` (IDE commit button, plain terminal) `scan.sh` re-runs itself through `devbox run` when no JDK is on PATH.

### Quality gate (`rnd-strict`, assigned to the project)

The gate fails on any of: a vulnerability, a bug, more than 10 code smells, coverage below 80%,
duplication above 3%, or a security / reliability / maintainability rating worse than A.
`SonarcubeApplication` is excluded from coverage (bootstrap only).

> Community Build keeps **one** analysis per project and has no branch analysis.
> The hook and Jenkins both write to the same project, so the dashboard shows whichever scan ran last,
> including a developer's uncommitted-but-staged work.

## Seeing a failure

Copy a bad example into the sources, stage it and commit:

| File in `demo/bad-examples/` | Fails at | Why |
|---|---|---|
| `LegacyUtil.java.txt` | lint | empty catch block, `==` on strings |
| `DemoService.java.txt` | Sonar gate | two bugs (null dereference, identical operands), untested code (coverage 52%) |

```bash
cp demo/bad-examples/DemoService.java.txt src/main/java/com/altama/sonarcube/DemoService.java
git add -A && git commit -m "try bad code"     # rejected by the hook
rm src/main/java/com/altama/sonarcube/DemoService.java
```

## Jenkins

The `Jenkinsfile` is a template: one generic job builds any Java + Maven-wrapper repo that is configured like
this one (Checkstyle and JaCoCo in `pom.xml`). Stages:

```
Prerequisites -> Checkout (REPO_URL @ BRANCH) -> Test -> Lint -> SonarQube scan + quality gate -> Build (jar archived)
```

| Parameter | Meaning |
|---|---|
| `REPO_URL`, `BRANCH` | what to build |
| `SONAR_PROJECT_KEY`, `SONAR_PROJECT_NAME` | project in SonarQube (the first scan creates it) |
| `SCAN_BRANCHES` | branches that are scanned (default `main,master`). Community Build keeps one analysis per project, so other branches run test, lint and build only |
| `REQUIRED_JAVA` | minimum Java major version checked in Prerequisites (default `21`) |
| `JDK_HOME` | optional: path of a JDK 21 on the Jenkins node (empty = the node's `JAVA_HOME` / `java`). Needs no admin rights |
| `SONAR_TOKEN_INPUT` | optional: Sonar token typed per build (see token sources below) |
| `GIT_CREDENTIALS_ID` | optional: Jenkins credential id for a private repo |

```bash
cp .env.example .env     # set SONAR_URL, SONAR_TOKEN, JENKINS_ADMIN_PASSWORD
devbox run jenkins-up    # = docker compose --env-file .env -f jenkins/docker-compose.yml up -d --build
# open http://localhost:8080, log in, job "sonar-pipeline" > Build with Parameters
```

Jenkins plugins needed: **Pipeline**, **Git**, **Credentials Binding**. Nothing else (no SonarQube, JUnit or
Timestamper plugin). Also set the global env var `SONAR_URL` and give the pipeline a Sonar token in any one of
these ways (first one found wins; the `jenkins/` image creates the credential for you):

| Token source | Where | Needs admin? |
|---|---|---|
| Build parameter `SONAR_TOKEN_INPUT` | typed in *Build with Parameters*, password type (masked) | no |
| Global env var `SONAR_TOKEN` | Manage Jenkins > System > Global properties > Environment variables | yes, and it is stored in plain text |
| Credential `sonar-token` (Secret text) | Manage Jenkins > Credentials | yes, recommended |

The first stage, **Prerequisites**, runs before anything is checked out or built. It prints every parameter
that this build uses (token and password values are masked), then checks: `bash`/`git`/`curl`, Java and `javac`
against `REQUIRED_JAVA`, that `REPO_URL` and `BRANCH` are readable, Maven Central, and (when the branch is
scanned) that SonarQube is UP, a token exists and it is valid. Problems are `[FAIL]` lines and stop the build.

When a build fails, the end of the console log shows the failed stage, the reason and, for the Sonar stage,
the red quality gate conditions (metric, actual value, limit). The same stage name is the build description.
There is no mail or chat notification.

The image is configured by code (`jenkins/casc.yaml`): admin user, the `sonar-token` credential, `SONAR_URL`
and the `sonar-pipeline` job all exist on first boot. There is no Docker-in-Docker and no SonarQube webhook:
the scan waits for the gate by polling. Needs Docker with your user in the `docker` group.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `SONAR_TOKEN is not set` | create `.env` from `.env.example` |
| `SONAR_URL is not set` / `SONAR_PROJECT_KEY is not set` | same: fill them in `.env` |
| `Insufficient privileges` / 403 on scan | your token's account needs *Execute Analysis* (and *Create Projects* for a new key) |
| `QUALITY GATE STATUS: FAILED` | open the printed dashboard URL, fix the listed issues |
| Checkstyle violations | the console lists file and line; rules are in `config/checkstyle.xml` |
| Hook does not run | `git config core.hooksPath` should print `.githooks`; run `devbox shell` or set it manually |
| `bad interpreter` / `\r` errors on Windows | the repo forces LF for `*.sh` and hooks; re-clone or `git rm --cached -r . && git reset --hard` |
| Hook silently does nothing | the hook files lost their executable bit: `chmod +x .githooks/pre-commit scan.sh mvnw` and `git config core.fileMode true` |
| Jenkins fails at *SonarQube scan* with `SONAR_URL is not set` | start it with `devbox run jenkins-up` (reads `.env`) |
| Jenkins: `release version 21 not supported` / `no usable Java 21` | the node's JDK is older than `java.version` in `pom.xml`. Install JDK 21, then set `JAVA_HOME` in Manage Jenkins > System > Global properties, or pass its path in the `JDK_HOME` parameter |
| Jenkins container exits at boot | `JENKINS_ADMIN_PASSWORD`, `SONAR_URL` or `SONAR_TOKEN` missing in `.env` (compose refuses to start) |
