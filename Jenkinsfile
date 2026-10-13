// Reusable pipeline template for a Java + Maven wrapper project:
//   prerequisites -> checkout BRANCH -> test -> lint -> SonarQube scan + quality gate -> build
// Everything project-specific is a build parameter, so one job can build any repo:
//   REPO_URL, BRANCH, SONAR_PROJECT_KEY, SONAR_PROJECT_NAME.
// The target project's pom needs the Checkstyle and JaCoCo plugins configured like this repo's pom.xml.
//
// Plugins needed: Pipeline, Git, Credentials Binding. Nothing else (no JUnit, Timestamper or SonarQube plugin);
// unit tests are the Spring Boot tests run by Maven Surefire, and their result is the console log.
// Needed from Jenkins: env SONAR_URL (Manage Jenkins > System > Global properties) and the Sonar token.
// The token is read from the first of these that is set:
//   1. build parameter SONAR_TOKEN_INPUT   (password type, masked; needs no admin rights)
//   2. global env var SONAR_TOKEN          (Manage Jenkins > System > Global properties)
//   3. credential "sonar-token"            (Secret text; what jenkins/casc.yaml creates)
// No Docker agent and no SonarQube webhook: the scan polls for the gate (sonar.qualitygate.wait),
// so it also works when SonarQube cannot reach this Jenkins.
//
// On failure there is no mail or chat message. The end of the console log says which stage failed and why,
// including the red quality gate conditions, and the build list shows the same in the build description.

// One-line explanation per stage, printed at the end of a failed build.
def failureHint(String stageName) {
    switch (stageName) {
        case 'Prerequisites':
            return 'The environment is not ready. Each problem is a [FAIL] line in the Prerequisites output (Java, token, SonarQube, repository).'
        case 'Checkout':
            return 'Cannot clone REPO_URL at BRANCH. Check the URL, the branch name, and GIT_CREDENTIALS_ID for a private repo.'
        case 'Test':
            return 'A unit test failed, the code does not compile, or the node has a JDK that is too old or only a JRE (see the Java check above). Surefire lists each failing test (search the log for FAILURE or ERROR).'
        case 'Lint':
            return 'Checkstyle found violations. Each one is listed above as file:line: message. Fix them in the code.'
        case 'SonarQube scan':
            return 'The scanner failed or the quality gate is red. The failed gate conditions are listed below when available.'
        case 'Build':
            return 'Packaging failed. See the Maven error above.'
        default:
            return 'See the console log above for the first error.'
    }
}

// Runs the Maven wrapper and keeps a copy of its output in .pipeline.log, so a failed build can quote the real error.
def mvn(String args) {
    sh """#!/bin/bash
set -o pipefail
./mvnw -B ${args} 2>&1 | tee -a .pipeline.log
"""
}

// Runs body with SONAR_TOKEN available to sh steps. The shell scripts below also accept SONAR_TOKEN_INPUT.
def withSonarToken(Closure body) {
    if (params.SONAR_TOKEN_INPUT?.trim() || env.SONAR_TOKEN?.trim()) {
        body()
    } else {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) { body() }
    }
}

// Stage "Prerequisites": show what this build will use (secrets masked) and verify the node before any work starts.
def checkPrerequisites() {
    def willScan = params.SCAN_BRANCHES.split(',').collect { it.trim() }.contains(params.BRANCH)

    echo '=================== PARAMETERS USED BY THIS BUILD ==================='
    for (name in params.keySet()) {
        def value = params[name]?.toString() ?: ''
        def secret = ['TOKEN', 'PASSWORD', 'SECRET'].any { name.toUpperCase().contains(it) }
        def shown = secret ? (value.trim() ? '****** (set, masked)' : '(empty)') : (value ?: '(empty)')
        echo "${name} = ${shown}"
    }
    echo "SONAR_URL (from Jenkins) = ${env.SONAR_URL ?: '(NOT SET)'}"
    echo "JAVA_HOME (effective)    = ${env.JAVA_HOME ?: '(not set, java from PATH)'}"
    echo "Node / workspace         = ${env.NODE_NAME} / ${env.WORKSPACE}"
    echo "SonarQube scan           = ${willScan ? 'YES' : 'NO (BRANCH is not in SCAN_BRANCHES)'}"

    // where the Sonar token comes from (the value is never printed)
    def tokenSource = 'none'
    if (params.SONAR_TOKEN_INPUT?.trim()) {
        tokenSource = 'build parameter SONAR_TOKEN_INPUT'
    } else if (env.SONAR_TOKEN?.trim()) {
        tokenSource = 'global environment variable SONAR_TOKEN'
    } else {
        try {
            withCredentials([string(credentialsId: 'sonar-token', variable: 'CHECK_ONLY')]) {
                tokenSource = "credential 'sonar-token'"
            }
        } catch (Exception e) {
            tokenSource = 'none'
        }
    }
    echo "Sonar token source       = ${tokenSource}"

    def checks = '''#!/bin/bash
rm -f .pipeline.log
fail=0
ok()   { echo "[ OK ]   $*"; }
warn() { echo "[WARN]   $*"; }
bad()  { echo "[FAIL]   $*"; echo "[ERROR] $*" >> .pipeline.log; fail=1; }
echo "=================== PREREQUISITES ==================="

for t in bash git curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $("$t" --version 2>&1 | head -1 | cut -c1-70)"; else bad "$t is not installed on this node"; fi
done

need="${REQUIRED_JAVA:-21}"
case "$need" in ''|*[!0-9]*) need=21 ;; esac
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
have=$("$JAVA" -version 2>&1 | grep -o 'version "[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
if [ -z "$have" ]; then
  bad "java not found (JAVA_HOME=${JAVA_HOME:-not set}). Install JDK $need, then set JAVA_HOME or the JDK_HOME parameter"
elif [ "$have" -lt "$need" ]; then
  bad "Java $have found but the project needs $need or newer. Set JAVA_HOME or the JDK_HOME parameter"
else
  ok "java $have (needs $need)"
fi
if command -v "$JAVAC" >/dev/null 2>&1; then ok "javac is present (JDK, not only a JRE)"; else bad "javac is missing: this is a JRE. Install the JDK package or point JDK_HOME at a full JDK"; fi

if [ -n "${GIT_CREDENTIALS_ID:-}" ]; then
  warn "private repository credential is set: access is checked at the Checkout stage"
elif GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads "$REPO_URL" "refs/heads/$BRANCH" >/dev/null 2>&1; then
  ok "repository is readable and branch '$BRANCH' exists"
else
  bad "cannot read $REPO_URL or it has no branch '$BRANCH'. Check the URL, the branch, the network, or set GIT_CREDENTIALS_ID"
fi

code=$(curl -sI -m 10 -o /dev/null -w '%{http_code}' https://repo.maven.apache.org/maven2/ 2>/dev/null || true)
if [ "$code" = "200" ]; then ok "Maven Central is reachable"; else warn "Maven Central answered '${code:-nothing}': fine only if this node uses a Maven mirror"; fi

if [ "${WILL_SCAN:-}" = "true" ]; then
  if [ "${TOKEN_SOURCE:-none}" = "none" ]; then
    bad "no Sonar token: set parameter SONAR_TOKEN_INPUT, global env SONAR_TOKEN, or credential sonar-token"
  elif [ -z "${SONAR_URL:-}" ]; then
    bad "SONAR_URL is not set (Manage Jenkins > System > Global properties > Environment variables)"
  else
    SONAR_TOKEN="${SONAR_TOKEN_INPUT:-${SONAR_TOKEN:-}}"
    st=$(curl -fsS -m 15 "$SONAR_URL/api/system/status" 2>/dev/null | grep -o '"status":"[A-Z_]*"' | head -1 || true)
    if [ "$st" = '"status":"UP"' ]; then ok "SonarQube is UP at $SONAR_URL"; else bad "SonarQube is not reachable or not UP at $SONAR_URL (answer: ${st:-none})"; fi
    valid=$(curl -fsS -m 15 -u "$SONAR_TOKEN:" "$SONAR_URL/api/authentication/validate" 2>/dev/null | grep -o '"valid":[a-z]*' || true)
    if [ "$valid" = '"valid":true' ]; then ok "Sonar token is valid"; else bad "Sonar token was rejected or could not be checked"; fi
  fi
else
  ok "Sonar scan is skipped for this branch, so SonarQube and the token are not checked"
fi

if [ "$fail" -ne 0 ]; then echo "Prerequisites FAILED: fix the [FAIL] lines above, nothing was built."; exit 1; fi
echo "All prerequisites are met."
'''
    withEnv(["WILL_SCAN=${willScan}", "TOKEN_SOURCE=${tokenSource}"]) {
        if (tokenSource == 'none') {
            sh(script: checks)
        } else {
            withSonarToken { sh(script: checks) }
        }
    }
}

// Asks SonarQube which gate conditions are red, so the log says why the gate failed.
def printSonarGateFailures() {
    try {
        withSonarToken {
            def body = sh(returnStdout: true, script: '''#!/bin/bash
SONAR_TOKEN="${SONAR_TOKEN_INPUT:-${SONAR_TOKEN:-}}"
curl -fsS -u "$SONAR_TOKEN:" "$SONAR_URL/api/qualitygates/project_status?projectKey=$SONAR_PROJECT_KEY"
''')
            def status = new groovy.json.JsonSlurperClassic().parseText(body).projectStatus
            if (status.status != 'ERROR') {
                echo "Quality gate status is ${status.status}, so the scanner itself failed: read the Maven error above (URL, token, permissions)."
                return
            }
            echo 'Quality gate FAILED. Red conditions:'
            status.conditions.findAll { it.status == 'ERROR' }.each { c ->
                def op = c.comparator == 'GT' ? '>' : (c.comparator == 'LT' ? '<' : c.comparator)
                echo " - ${c.metricKey}: actual ${c.actualValue}, fails when ${op} ${c.errorThreshold}"
            }
            echo "Details: ${env.SONAR_URL}/dashboard?id=${env.SONAR_PROJECT_KEY}"
        }
    } catch (Exception e) {
        echo "Could not read the gate details from SonarQube: ${e.message}"
    }
}

pipeline {
    agent any
    options {
        skipDefaultCheckout(true) // the job's SCM holds only this file; the project is checked out below
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }
    parameters {
        string(name: 'REPO_URL', defaultValue: 'https://github.com/MaulanaFahrulGits/sonarcube.git',
               description: 'Git repository to build')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Branch to check out')
        string(name: 'SONAR_PROJECT_KEY', defaultValue: 'my-project',
               description: 'SonarQube project key (the first scan creates the project)')
        string(name: 'SONAR_PROJECT_NAME', defaultValue: '',
               description: 'Display name in SonarQube (empty = same as the key)')
        string(name: 'SCAN_BRANCHES', defaultValue: 'main,master',
               description: 'Only these branches are scanned: Community Build keeps one analysis per project, so other branches would overwrite it')
        password(name: 'SONAR_TOKEN_INPUT', defaultValue: '',
                 description: 'SonarQube token. Only if you cannot add the sonar-token credential or a global SONAR_TOKEN (empty = use those)')
        string(name: 'REQUIRED_JAVA', defaultValue: '21',
               description: 'Minimum Java major version the node must have (checked before anything is built)')
        string(name: 'JDK_HOME', defaultValue: '',
               description: 'Path of a JDK on the Jenkins node, e.g. /usr/lib/jvm/java-21-openjdk-amd64 (empty = the node JAVA_HOME or java on PATH)')
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: '',
               description: 'Jenkins credential id for a private repository (empty = anonymous)')
    }
    environment {
        SONAR_PROJECT_KEY  = "${params.SONAR_PROJECT_KEY}"
        SONAR_PROJECT_NAME = "${params.SONAR_PROJECT_NAME}"
        JAVA_HOME          = "${params.JDK_HOME?.trim() ? params.JDK_HOME.trim() : (env.JAVA_HOME ?: '')}"
    }
    stages {
        stage('Prerequisites') {
            steps { script { checkPrerequisites() } }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Checkout') {
            steps {
                script {
                    if (!params.REPO_URL?.trim() || !params.BRANCH?.trim()) {
                        error 'REPO_URL and BRANCH must not be empty'
                    }
                }
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "refs/heads/${params.BRANCH}"]],
                    userRemoteConfigs: [[url: params.REPO_URL, credentialsId: params.GIT_CREDENTIALS_ID]],
                    extensions: [[$class: 'CleanBeforeCheckout']]
                ])
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Test') {
            steps {
                // fail early and clearly when the node's JDK is older than the project's <java.version>
                sh '''#!/bin/bash
set -eu
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
need=$(grep -o '<java.version>[0-9]*' pom.xml | head -1 | grep -o '[0-9]*$' || true)
need=${need:-21}
have=$("$JAVA" -version 2>&1 | grep -o 'version "[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
echo "Java on this node: ${have:-not found} (JAVA_HOME=${JAVA_HOME:-not set}); the project needs Java $need"
if [ -z "$have" ] || [ "$have" -lt "$need" ]; then
  echo "ERROR: this node has no usable Java $need. Install JDK $need and then either set JAVA_HOME in" >&2
  echo "       Manage Jenkins > System > Global properties, or give its path in the JDK_HOME build parameter." >&2
  exit 1
fi
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
if ! command -v "$JAVAC" >/dev/null 2>&1; then
  echo "ERROR: Java $have is installed but javac (the compiler) is missing: this is a JRE, not a JDK." >&2
  echo "       Install the JDK package (for example openjdk-$need-jdk) or point JDK_HOME at a full JDK." >&2
  exit 1
fi
'''
                // lint is bound to Maven's validate phase, so skip it here; it has its own stage below
                script { mvn '-Dcheckstyle.skip=true test jacoco:report' }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Lint') {
            steps { script { mvn 'checkstyle:check' } }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('SonarQube scan') {
            when {
                expression {
                    params.SCAN_BRANCHES.split(',').collect { it.trim() }.contains(params.BRANCH)
                }
            }
            steps {
                // the scanner reads the token from env SONAR_TOKEN, so it never appears on a command line
                script {
                    withSonarToken {
                        sh '''#!/bin/bash
set -eu -o pipefail
: "${SONAR_URL:?SONAR_URL is not set on this Jenkins (Manage Jenkins > System > Global properties)}"
SONAR_TOKEN="${SONAR_TOKEN_INPUT:-${SONAR_TOKEN:-}}"
: "${SONAR_TOKEN:?no Sonar token: set parameter SONAR_TOKEN_INPUT, global env SONAR_TOKEN or credential sonar-token}"
export SONAR_TOKEN
extra=()
if [ -n "${SONAR_PROJECT_NAME:-}" ]; then extra+=("-Dsonar.projectName=$SONAR_PROJECT_NAME"); fi
./mvnw -B org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.host.url="$SONAR_URL" \
  ${extra[@]+"${extra[@]}"} \
  -Dsonar.qualitygate.wait=true 2>&1 | tee -a .pipeline.log
'''
                    }
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Build') {
            steps {
                script { mvn '-DskipTests -Dcheckstyle.skip=true package' }
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: true
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        // stage('Deploy') { gcloud run deploy ... }  <- only reached when the gate is green
    }
    post {
        failure {
            script {
                def stageName = env.FAILED_STAGE ?: 'unknown'
                currentBuild.description = "FAILED at ${stageName}"
                echo '=================== WHY THIS BUILD FAILED ==================='
                echo "Stage : ${stageName}"
                echo "Reason: ${failureHint(stageName)}"
                sh(returnStatus: true, script: '''#!/bin/bash
if [ -f .pipeline.log ] && grep -qF '[ERROR]' .pipeline.log; then
  echo "--- first errors from the log ---"
  grep -F '[ERROR]' .pipeline.log | head -15
fi
''')
                if (stageName == 'SonarQube scan') {
                    printSonarGateFailures()
                }
                echo '============================================================='
            }
        }
        aborted {
            echo 'Build was aborted: manual stop or the 30 minute timeout was reached.'
        }
    }
}
