#!/usr/bin/env bash
# Pipeline stage "Prerequisites": check that this node can build, scan and deploy before any work starts.
# Prints [ OK ] / [WARN] / [FAIL]; every failure is also appended to .pipeline.log as [ERROR] so the final
# "why did it fail" block can quote it. Exits 1 when something is missing.
#
# Input (environment, set by the Jenkinsfile): WILL_SCAN, WILL_DEPLOY, TOKEN_SOURCE, DB_SOURCE, DB_URL,
# DOCKER_NETWORK, SONAR_URL, SONAR_TOKEN or SONAR_TOKEN_INPUT, JAVA_HOME.
cd "$(dirname "$0")/.."
rm -f .pipeline.log
fail=0
ok()   { echo "[ OK ]   $*"; }
warn() { echo "[WARN]   $*"; }
bad()  { echo "[FAIL]   $*"; echo "[ERROR] $*" >> .pipeline.log; fail=1; }

echo "=================== PREREQUISITES ==================="
echo "commit: $(git log -1 --format='%h %s' 2>/dev/null | cut -c1-90)"

# ---- tools ----
for t in bash git curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $("$t" --version 2>&1 | head -1 | cut -c1-70)"; else bad "$t is not installed on this node"; fi
done
if [ -x ./mvnw ]; then ok "mvnw is executable"; else bad "./mvnw is missing or not executable (chmod +x mvnw, then commit the mode)"; fi

# ---- java: the version pom.xml asks for ----
need=$(grep -o '<java.version>[0-9]*' pom.xml 2>/dev/null | head -1 | grep -o '[0-9]*$' || true)
need=${need:-21}
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
have=$("$JAVA" -version 2>&1 | grep -o 'version "[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
if [ -n "${JAVA_HOME:-}" ] && [ ! -x "$JAVA_HOME/bin/java" ]; then
  bad "JAVA_HOME=$JAVA_HOME has no bin/java on this node. Edit JAVA_HOME in the Jenkinsfile environment block to the real JDK $need path (ls /usr/lib/jvm)"
elif [ -z "$have" ]; then
  bad "java not found (JAVA_HOME=${JAVA_HOME:-not set}). Install JDK $need and set JAVA_HOME in the Jenkinsfile environment block"
elif [ "$have" -lt "$need" ]; then
  bad "Java $have found at JAVA_HOME=${JAVA_HOME:-PATH} but pom.xml needs $need or newer. Point JAVA_HOME in the Jenkinsfile environment block to a JDK $need"
else
  ok "java $have (pom.xml needs $need) at JAVA_HOME=${JAVA_HOME:-from PATH}"
  if command -v "$JAVAC" >/dev/null 2>&1; then ok "javac is present (JDK, not only a JRE)"; else bad "javac is missing: this is a JRE. Install the JDK package or point JAVA_HOME at a full JDK"; fi
fi

code=$(curl -sI -m 10 -o /dev/null -w '%{http_code}' https://repo.maven.apache.org/maven2/ 2>/dev/null || true)
if [ "$code" = "200" ]; then ok "Maven Central is reachable"; else warn "Maven Central answered '${code:-nothing}': fine only if this node uses a Maven mirror"; fi

# ---- SonarQube ----
if [ "${WILL_SCAN:-}" = "true" ]; then
  token="${SONAR_TOKEN_INPUT:-${SONAR_TOKEN:-}}"
  if [ "${TOKEN_SOURCE:-none}" = "none" ] || [ -z "$token" ]; then
    bad "no Sonar token: set parameter SONAR_TOKEN_INPUT, global env SONAR_TOKEN, or credential sonar-token"
  elif [ -z "${SONAR_URL:-}" ]; then
    bad "SONAR_URL is not set (Manage Jenkins > System > Global properties > Environment variables)"
  else
    status=$(curl -fsS -m 15 "$SONAR_URL/api/system/status" 2>/dev/null | grep -o '"status":"[A-Z_]*"' | head -1 || true)
    if [ "$status" = '"status":"UP"' ]; then ok "SonarQube is UP at $SONAR_URL"; else bad "SonarQube is not reachable or not UP at $SONAR_URL (answer: ${status:-none})"; fi
    valid=$(curl -fsS -m 15 -u "$token:" "$SONAR_URL/api/authentication/validate" 2>/dev/null | grep -o '"valid":[a-z]*' || true)
    if [ "$valid" = '"valid":true' ]; then ok "Sonar token is valid"; else bad "Sonar token was rejected or could not be checked"; fi
  fi
else
  ok "Sonar scan is skipped for this branch, so SonarQube and the token are not checked"
fi

# ---- deploy: docker, network, database ----
if [ "${WILL_DEPLOY:-}" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    bad "docker is not installed on this node"
  elif ! docker info >/dev/null 2>&1; then
    bad "docker is installed but this user cannot use it. Add the Jenkins user to the docker group and restart Jenkins"
  else
    ok "docker works: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if [ -n "${DOCKER_NETWORK:-}" ]; then
      if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then ok "docker network '$DOCKER_NETWORK' exists"; else bad "docker network '$DOCKER_NETWORK' does not exist. Start the database first: devbox run startup"; fi
    fi
    rest="${DB_URL#*://}"
    dbhost="${rest%%[:/]*}"
    if docker ps --format '{{.Names}}' | grep -qx "$dbhost"; then
      ok "database container '$dbhost' is running"
      # the application gets its database login from this container, so nothing has to be typed in Jenkins
      if [ "${DB_SOURCE:-none}" != "none" ]; then
        ok "database password comes from ${DB_SOURCE}"
      elif docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$dbhost" 2>/dev/null | grep -q '^POSTGRES_PASSWORD='; then
        ok "database login is read from the running container '$dbhost' (POSTGRES_USER / POSTGRES_PASSWORD)"
      else
        bad "container '$dbhost' does not expose POSTGRES_PASSWORD. Set the global env DB_PASSWORD or the credential db-password"
      fi
    elif [ "${DB_SOURCE:-none}" != "none" ]; then
      warn "no running container named '$dbhost': using the database password from ${DB_SOURCE}"
    else
      bad "no running container named '$dbhost' and no DB_PASSWORD env / db-password credential. Start the database (devbox run startup) or provide the password"
    fi
  fi
else
  ok "deploy is off for this build, so docker and the database are not checked"
fi

if [ "$fail" -ne 0 ]; then echo "Prerequisites FAILED: fix the [FAIL] lines above, nothing was built."; exit 1; fi
echo "All prerequisites are met."
