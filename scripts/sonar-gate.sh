#!/usr/bin/env bash
# Make sure the SonarQube project exists and uses OUR quality gate (default: rnd-strict), so the scan is judged by
# it and not by the server's default "Sonar way". Creates the gate with strict conditions if it does not exist.
# An existing gate is never modified.
#
# Needs a token that may create projects and assign gates (Administer Quality Gates to create the gate itself).
# Input: SONAR_URL, SONAR_TOKEN, SONAR_PROJECT_KEY, SONAR_PROJECT_NAME (optional), SONAR_QUALITY_GATE.
set -euo pipefail
: "${SONAR_URL:?SONAR_URL is not set}" "${SONAR_TOKEN:?SONAR_TOKEN is not set}"
: "${SONAR_PROJECT_KEY:?SONAR_PROJECT_KEY is not set}" "${SONAR_QUALITY_GATE:?SONAR_QUALITY_GATE is not set}"
key=$SONAR_PROJECT_KEY
name=${SONAR_PROJECT_NAME:-$SONAR_PROJECT_KEY}
gate=$SONAR_QUALITY_GATE

# api GET|POST <path> [curl args...]: prints the body, exit 1 with a readable error on HTTP >= 400
api() {
  local method=$1 path=$2; shift 2
  local out code
  out=$(mktemp)
  code=$(curl -sS -m 30 -o "$out" -w '%{http_code}' -u "$SONAR_TOKEN:" -X "$method" "$SONAR_URL/api/$path" "$@") || { echo "[ERROR] cannot reach $SONAR_URL"; rm -f "$out"; return 1; }
  if [ "$code" -ge 400 ]; then
    echo "[ERROR] SonarQube answered HTTP $code for $method api/$path: $(head -c 300 "$out")"
    rm -f "$out"; return 1
  fi
  cat "$out"; rm -f "$out"
}

# --- 1. the gate ---
if api GET "qualitygates/show?name=$gate" >/dev/null 2>&1; then
  echo "gate '$gate' exists on the server"
else
  echo "gate '$gate' does not exist: creating it with strict conditions on the whole code base"
  api POST qualitygates/create -d "name=$gate" >/dev/null
  # metric:operator:threshold (operator GT = fails when greater, LT = fails when lower; ratings: 1 = A)
  for c in bugs:GT:0 vulnerabilities:GT:0 code_smells:GT:10 coverage:LT:80 duplicated_lines_density:GT:3 \
           security_rating:GT:1 reliability_rating:GT:1 sqale_rating:GT:1; do
    IFS=: read -r metric op error <<<"$c"
    api POST qualitygates/create_condition -d "gateName=$gate" -d "metric=$metric" -d "op=$op" -d "error=$error" >/dev/null \
      || echo "[WARN] condition $metric was not added (an equal condition may already exist)"
  done
fi

# --- 2. the project (the first scan would create it with the server default gate, too late) ---
found=$(api GET "projects/search?projects=$key" | grep -o '"key":"[^"]*"' | head -1 || true)
if [ -z "$found" ]; then
  echo "project '$key' does not exist yet: creating it as '$name'"
  api POST projects/create -d "project=$key" -d "name=$name" >/dev/null
fi

# --- 3. assign ---
api POST qualitygates/select -d "gateName=$gate" -d "projectKey=$key" >/dev/null
used=$(api GET "qualitygates/get_by_project?project=$key" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "quality gate used for project '$key': $used"
if [ "$used" != "$gate" ]; then echo "[ERROR] the project still uses '$used' instead of '$gate'"; exit 1; fi
