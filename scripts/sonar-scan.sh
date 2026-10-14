#!/usr/bin/env bash
# Pipeline stage "SonarQube scan": assign our quality gate, scan with Maven and wait for the gate verdict.
# Exit code 1 when the scan fails or the gate is red.
#
# Input: SONAR_URL, SONAR_TOKEN or SONAR_TOKEN_INPUT, SONAR_PROJECT_KEY, SONAR_PROJECT_NAME (default: the key),
#        SONAR_QUALITY_GATE (empty = leave the gate assignment of the server alone).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SONAR_URL:?SONAR_URL is not set on this Jenkins (Manage Jenkins > System > Global properties)}"
SONAR_TOKEN="${SONAR_TOKEN_INPUT:-${SONAR_TOKEN:-}}"
: "${SONAR_TOKEN:?no Sonar token: set parameter SONAR_TOKEN_INPUT, global env SONAR_TOKEN or credential sonar-token}"
: "${SONAR_PROJECT_KEY:?SONAR_PROJECT_KEY is not set}"
export SONAR_TOKEN   # the scanner reads it from the environment, so it never appears on a command line
export SONAR_PROJECT_NAME="${SONAR_PROJECT_NAME:-$SONAR_PROJECT_KEY}"

if [ -n "${SONAR_QUALITY_GATE:-}" ]; then
  scripts/sonar-gate.sh
else
  echo "SONAR_QUALITY_GATE is empty: the gate assigned on the server decides"
fi

./mvnw -B org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.projectName="$SONAR_PROJECT_NAME" \
  -Dsonar.host.url="$SONAR_URL" \
  -Dsonar.qualitygate.wait=true
