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
├── Dockerfile               runtime image of the APPLICATION (the pipeline copies the built jar in)
├── startup/                 the learning environment: docker-compose.yml (Postgres + Jenkins) and jenkins/ (image, plugins, JCasC)
├── scripts/deploy.sh        stop the running app, start the new image, wait healthy, roll back on failure
├── scripts/smoke-test.sh    GET /api/students must return data
├── config/checkstyle.xml    lint rules (Checkstyle)
├── .githooks/pre-commit     blocks the commit when lint, tests or the Sonar gate fail
├── scan.sh                  lint + test + coverage + Sonar scan, one command (used by the hook)
├── devbox.json              reproducible dev environment (JDK 21, git, curl) + helper scripts
├── .env.example             copy to .env: SONAR_URL, SONAR_TOKEN, SONAR_PROJECT_KEY, Jenkins admin
├── Jenkinsfile              CI/CD template: checkout, test, lint, Sonar scan + gate, build, image, deploy app, smoke test
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
| `devbox run startup` / `startup-down` | start / stop the local Postgres + Jenkins (`startup/docker-compose.yml`) |
| `devbox run db-up` | only the database |
| `devbox run run` | the app on the host against that database, http://localhost:8080/api/students |
| `devbox run jenkins-logs` | follow the Jenkins log |

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

## Learning environment (`startup/`)

Everything you need to practise the whole flow (code, test, lint, SonarQube scan, build an image, run it) on one
machine. Only the SonarQube server is yours; Jenkins, the database and the application run in docker.

```bash
cp .env.example .env            # set SONAR_URL and SONAR_TOKEN (and SONAR_PROJECT_KEY)
devbox run startup              # = docker compose --env-file .env -f startup/docker-compose.yml up -d --build
```

| Service | URL / name | Login |
|---|---|---|
| Jenkins | http://localhost:8080 | `admin` / `admin` (job `sonar-pipeline` already exists) |
| Postgres | container `sonarcube-db`, host port `5433` | user `sonarcube`, password `sonarcube-learn` |
| Application (after a green pipeline) | http://127.0.0.1:8081/api/students | none |

Then: open Jenkins, job `sonar-pipeline` > *Build with Parameters*, set `SONAR_PROJECT_KEY` (the first run only
registers the parameters and fails, that is normal), run it, and `curl http://127.0.0.1:8081/api/students`.

The passwords above are hardcoded on purpose in `startup/docker-compose.yml`: it is a throw-away local setup and
there is nothing to configure. Your SonarQube URL and token are the only values that come from your `.env`.

The pipeline only ships the **application**. Jenkins and the database are infrastructure that you start once
with `startup`, like in a real project. Jenkins uses your machine's docker through the mounted `docker.sock`, so
the image it builds and the container it starts appear in your own `docker ps`.

`GET /api/students` returns the rows of the `students` table with the letter grade of each score
(`db/init.sql` has the schema and four sample rows).

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
| `DB_URL`, `DB_USER`, `DOCKER_NETWORK` | how the app reaches the database (defaults match `startup/docker-compose.yml`) |
| `DB_PASSWORD_INPUT` | optional: DB password typed per build |
| `GIT_CREDENTIALS_ID` | optional: Jenkins credential id for a private repo |

**What the Jenkins node needs** (the image in `startup/jenkins/` already has all of it): Pipeline, Git and
Credentials Binding plugins; JDK 21 (set `JAVA_HOME` in the `environment` block of the `Jenkinsfile` to its path,
default `/usr/lib/jvm/java-21-openjdk`); `git`, `curl`; for the deploy `docker` usable by the Jenkins user; and the
database already running (`devbox run startup` or `db-up`). Also the global env var `SONAR_URL`.

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

`startup/jenkins/` is the Jenkins image (JCasC in `casc.yaml`): user `admin`, credentials `sonar-token` (from your
`.env`) and `db-password`, the global env `SONAR_URL`, the job `sonar-pipeline` (Jenkinsfile of branch `rnd`),
and the docker CLI. There is no SonarQube webhook: the scan waits for the gate by polling.

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
| App fails at start with `Could not resolve placeholder 'DB_PASSWORD'` | `DB_PASSWORD` is not set; the container gets it from the pipeline (credential `db-password`), `devbox run run` sets it itself |
| `password authentication failed for user "sonarcube"` | the password differs from the one the database volume was created with (`sonarcube-learn`); `devbox run startup-down` then `docker volume rm sonarcube-startup_sonarcube-pgdata` to recreate |
| Deploy: `docker network 'sonarcube-net' does not exist` | the database was never started: `devbox run startup` |
| Deploy: `this user cannot use it` (own Jenkins, not `startup/`) | add the `jenkins` user to the `docker` group and restart Jenkins |
| Hook silently does nothing | the hook files lost their executable bit: `chmod +x .githooks/pre-commit scan.sh mvnw` and `git config core.fileMode true` |
| Prerequisites: `SonarQube is not reachable` | `SONAR_URL` in `.env` is still the example value, or the Jenkins container cannot reach your SonarQube (VPN, DNS). After editing `.env` run `devbox run startup` again |
| Jenkins: `release version 21 not supported` / `no usable Java 21` / `JAVA_HOME=... has no bin/java` | the JDK path in the Jenkinsfile `environment` block (`JAVA_HOME = "/usr/lib/jvm/java-21-openjdk"`) does not exist on your server or is older than `java.version` in `pom.xml`. Edit that path (`ls /usr/lib/jvm`) |
