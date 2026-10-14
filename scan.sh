#!/usr/bin/env bash
# Lint + unit tests + coverage + SonarQube scan. Exits non-zero if any of them, or the quality gate, fails.
# Settings come from the environment or a git-ignored .env file (copy .env.example).
# Project-specific values are variables, so the same script works for any Maven project:
#   SONAR_URL, SONAR_TOKEN, SONAR_PROJECT_KEY (required), SONAR_PROJECT_NAME (optional, default: the key),
#   SONAR_QUALITY_GATE (optional: assign this gate to the project before the scan, e.g. rnd-strict).
set -euo pipefail
cd "$(dirname "$0")"
# tr: tolerate a .env saved with Windows (CRLF) line endings, which would leave a \r in every value
if [ -f .env ]; then set -a; . <(tr -d '\r' < .env); set +a; fi

: "${SONAR_URL:?SONAR_URL is not set. Copy .env.example to .env and fill it in (see README).}"
: "${SONAR_PROJECT_KEY:?SONAR_PROJECT_KEY is not set. Copy .env.example to .env and fill it in (see README).}"
: "${SONAR_TOKEN:?SONAR_TOKEN is not set. Copy .env.example to .env and fill in your token (see README).}"

# No JDK on PATH (IDE commit button, plain terminal): borrow devbox's environment instead of failing in mvnw.
if ! command -v java >/dev/null 2>&1 && [ ! -x "${JAVA_HOME:-/nonexistent}/bin/java" ]; then
  if [ -z "${SCAN_IN_DEVBOX:-}" ] && command -v devbox >/dev/null 2>&1; then
    SCAN_IN_DEVBOX=1 exec devbox run ./scan.sh
  fi
  echo "scan.sh: no JDK 21 found. Run inside 'devbox shell' (recommended) or install JDK 21." >&2
  exit 1
fi

# the dashboard name defaults to the key (without it Sonar would take <name> from pom.xml)
SONAR_PROJECT_NAME=${SONAR_PROJECT_NAME:-$SONAR_PROJECT_KEY}

# optional: make the project use our quality gate (needs a token that may assign gates)
if [ -n "${SONAR_QUALITY_GATE:-}" ]; then
  SONAR_URL=$SONAR_URL SONAR_TOKEN=$SONAR_TOKEN SONAR_PROJECT_KEY=$SONAR_PROJECT_KEY \
    SONAR_PROJECT_NAME=$SONAR_PROJECT_NAME SONAR_QUALITY_GATE=$SONAR_QUALITY_GATE scripts/sonar-gate.sh
fi

# `verify` already runs Checkstyle (validate phase), unit tests and the JaCoCo report.
./mvnw -B verify org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.host.url="$SONAR_URL" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.projectName="$SONAR_PROJECT_NAME" \
  -Dsonar.qualitygate.wait=true # exit code 1 when the gate fails, like the quality gate stage in Jenkins

echo "Dashboard: $SONAR_URL/dashboard?id=$SONAR_PROJECT_KEY"
