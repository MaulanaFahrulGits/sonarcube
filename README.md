# sonarcube

Spring Boot (Java 21) sample used to explore SonarQube + Jenkins on GCP serverless.
Every commit is gated locally (lint, unit tests, SonarQube quality gate), and Jenkins runs the same checks.

- SonarQube: Community Build. Server URL, token and project key are variables in `.env` (see `.env.example`).
- Research notes and findings: [SONAR-RESEARCH.md](SONAR-RESEARCH.md)
- Change log of what exists and why: [.project/history.md](.project/history.md)

## Project structure

```
.
├── src/main/java/...        application: GET /api/students reads Postgres (GradeService is the sample logic)
├── src/test/java/...        JUnit 5 tests (H2 in memory, no database needed)
├── db/init.sql              schema + sample data (Postgres first start, and the tests)
├── docker-compose.yml       the DATABASE only (separate infrastructure, not started by the pipeline)
├── Dockerfile               runtime image of the application (the pipeline copies the built jar in)
├── scripts/deploy.sh        stop the running app, start the new image, wait healthy, roll back on failure
├── scripts/smoke-test.sh    GET /api/students must return data
├── config/checkstyle.xml    lint rules (Checkstyle)
├── .githooks/pre-commit     blocks the commit when lint, tests or the Sonar gate fail
├── scan.sh                  lint + test + coverage + Sonar scan, one command (used by the hook)
├── devbox.json              reproducible dev environment (JDK 21, git, curl) + helper scripts
├── .env.example             copy to .env: SONAR_URL, SONAR_TOKEN, SONAR_PROJECT_KEY, Jenkins admin
├── Jenkinsfile              CI/CD template: checkout, test, lint, Sonar scan + gate, build, image, deploy app, smoke test
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
| `devbox run run` | start the app on the host (needs `devbox run db-up` and `DB_PASSWORD` in `.env`) |
| `devbox run db-up` / `db-down` | start / stop the Postgres container |
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

## Application and database

`GET /api/students` returns the rows of the `students` table with the letter grade of each score.

```bash
devbox run db-up      # Postgres in docker (docker-compose.yml), needs DB_PASSWORD in .env
devbox run run        # the app on the host, http://localhost:8080/api/students
devbox run db-down    # stop the database (data stays in the volume; add -v by hand to wipe it)
```

The database is **separate infrastructure**: start it once. The Jenkins pipeline only ships the application
container, like a real project; it never starts or stops the database. The application reaches it through the
docker network `sonarcube-net` as `sonarcube-db:5432`.

## Git credentials for this project

`git push` / `git pull` need a GitHub token. Put it in the git-ignored `.env` as `TOKEN_GIT=...` (fine-grained
token for this repository, *Contents: Read and write*). `scripts/git-credential-env` hands it to git only for
`github.com` and only inside this repository: `devbox shell` configures that automatically, or run

```bash
git config --local credential.https://github.com.helper '!bash "$(git rev-parse --show-toplevel)/scripts/git-credential-env"'
```

The token is never written to `.git/config`, never committed, and other repositories are not affected.

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

The `Jenkinsfile` is a template: one generic job builds and ships any Java + Maven-wrapper repo that is configured
like this one (Checkstyle and JaCoCo in `pom.xml`, a `Dockerfile` that copies `target/*.jar`). Stages:

```
Checkout (REPO_URL @ BRANCH) -> Prerequisites -> Test -> Lint -> SonarQube scan + quality gate -> Build (jar)
-> Image (docker build) -> Deploy (the application container only) -> Smoke test (GET /api/students)
```

Image, Deploy and Smoke test run only when `DEPLOY` is on **and** the branch was scanned, so only code that
passed the quality gate is ever started.

| Parameter | Meaning |
|---|---|
| `REPO_URL`, `BRANCH` | what to build (`BRANCH` default `rnd`) |
| `SONAR_PROJECT_KEY`, `SONAR_PROJECT_NAME` | project in SonarQube (the first scan creates it) |
| `SCAN_BRANCHES` | branches that are scanned and deployed (default `main,master,rnd`). Community Build keeps one analysis per project, so scanning another branch overwrites the previous analysis |
| `SONAR_TOKEN_INPUT` | optional: Sonar token typed per build (see secret sources below) |
| `DEPLOY` | build the image and (re)start the app after a green scan (default on) |
| `IMAGE_NAME`, `APP_PORT` | image and container name (`sonarcube`), host port on 127.0.0.1 (`8081`) |
| `DB_URL`, `DB_USER`, `DOCKER_NETWORK` | how the app reaches the database (defaults match `docker-compose.yml`) |
| `DB_PASSWORD_INPUT` | optional: DB password typed per build |
| `GIT_CREDENTIALS_ID` | optional: Jenkins credential id for a private repo |

**What the Jenkins node needs:** Pipeline, Git and Credentials Binding plugins; JDK 21 (set `JAVA_HOME` in the
`environment` block of the `Jenkinsfile` to its path, default `/usr/lib/jvm/java-21-openjdk`); `git`, `curl`;
and, for the deploy, `docker` usable by the `jenkins` user (member of the `docker` group). The database must
already be running (`devbox run db-up`). Also set the global env var `SONAR_URL`.

Secrets (Sonar token, DB password) are read from the first of these that is set:

| Source | Sonar token | DB password | Needs admin? |
|---|---|---|---|
| Build parameter (password type, masked) | `SONAR_TOKEN_INPUT` | `DB_PASSWORD_INPUT` | no |
| Global env var (Manage Jenkins > System > Global properties) | `SONAR_TOKEN` | `DB_PASSWORD` | yes, plain text |
| Credential (Secret text) | `sonar-token` | `db-password` | yes, recommended |

**Prerequisites** runs right after checkout. It prints every parameter this build uses (secret values are
masked), then checks: `bash`/`git`/`curl`, Java and `javac` against `<java.version>` in `pom.xml`, `mvnw`,
Maven Central, and when the branch is scanned that SonarQube is UP and the token valid, and when it will
deploy that docker works, the network exists, the database container runs and a DB password is available.
Problems are `[FAIL]` lines and stop the build before anything is built.

**Deploy** (`scripts/deploy.sh`): if the app container runs it is stopped, the new image is started with the DB
settings as environment variables, and the script waits for the container healthcheck. If the new version does not
become healthy the previous one is started again with its own settings, and the build still fails. Images are
tagged with the build number and `latest` and stay in the node's local docker (no registry, no push).

When a build fails, the end of the console log shows the failed stage, the reason and the first errors,
including the red quality gate conditions for the Sonar stage. There is no mail or chat notification.

`jenkins/` is a ready-made Jenkins image (JCasC: admin user, `sonar-token` credential, `SONAR_URL`, the
`sonar-pipeline` job). It has no docker CLI, so use it with `DEPLOY` off, or run Jenkins on a host with docker.

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
| App fails at start with `Could not resolve placeholder 'DB_PASSWORD'` | `DB_PASSWORD` is not set; the container gets it from the pipeline, `devbox run run` from `.env` |
| `password authentication failed for user "sonarcube"` | the password differs from the one the database volume was created with. Same value as in `.env`, or `docker compose down -v` to recreate |
| Deploy: `docker network 'sonarcube-net' does not exist` | the database was never started: `devbox run db-up` |
| Deploy: `this user cannot use docker` | add the `jenkins` user to the `docker` group and restart Jenkins |
| Hook silently does nothing | the hook files lost their executable bit: `chmod +x .githooks/pre-commit scan.sh mvnw` and `git config core.fileMode true` |
| Jenkins fails at *SonarQube scan* with `SONAR_URL is not set` | start it with `devbox run jenkins-up` (reads `.env`) |
| Jenkins: `release version 21 not supported` / `no usable Java 21` / `JAVA_HOME=... has no bin/java` | the JDK path in the Jenkinsfile `environment` block (`JAVA_HOME = "/usr/lib/jvm/java-21-openjdk"`) does not exist on your server or is older than `java.version` in `pom.xml`. Edit that path (`ls /usr/lib/jvm`) |
| Jenkins container exits at boot | `JENKINS_ADMIN_PASSWORD`, `SONAR_URL` or `SONAR_TOKEN` missing in `.env` (compose refuses to start) |
