// Reusable pipeline template for a Java + Maven wrapper project that ships as a Docker image:
//   checkout BRANCH -> prerequisites -> test -> lint -> SonarQube scan + gate -> build jar
//   -> docker image -> deploy the application container -> smoke test
// Like a real project, the pipeline only brings up the APPLICATION. The database is separate infrastructure
// (docker-compose.yml in this repo, started once by a developer); the app container just connects to it.
// Everything project-specific is a build parameter, so one job can build any repo.
//
// Plugins needed: Pipeline, Git, Credentials Binding. Nothing else.
// Java: JAVA_HOME is set in the environment block below (edit the path for your server).
// Needed from Jenkins: env SONAR_URL (Manage Jenkins > System > Global properties), a Sonar token, and for the
// deploy a DB password. A secret is read from the first of these that is set:
//   1. build parameter (SONAR_TOKEN_INPUT / DB_PASSWORD_INPUT)  password type, masked, needs no admin rights
//   2. global env var   (SONAR_TOKEN / DB_PASSWORD)             Manage Jenkins > System > Global properties
//   3. credential       ("sonar-token" / "db-password")         Secret text
// The deploy needs `docker` usable by the jenkins user on this node.
//
// On failure there is no mail or chat message. The end of the console log says which stage failed and why.

// One-line explanation per stage, printed at the end of a failed build.
def failureHint(String stageName) {
    switch (stageName) {
        case 'Checkout':
            return 'Cannot clone REPO_URL at BRANCH. Check the URL, the branch name, and GIT_CREDENTIALS_ID for a private repo.'
        case 'Prerequisites':
            return 'The environment is not ready. Each problem is a [FAIL] line in the Prerequisites output (Java, docker, token, SonarQube, database). If there is none, the Jenkinsfile itself threw: read the exception printed after "Also:".'
        case 'Test':
            return 'A unit test failed or the code does not compile. Surefire lists each failing test (search the log for FAILURE or ERROR).'
        case 'Lint':
            return 'Checkstyle found violations. Each one is listed above as file:line: message. Fix them in the code.'
        case 'SonarQube scan':
            return 'The scanner failed or the quality gate is red. The failed gate conditions are listed below when available.'
        case 'Build':
            return 'Packaging failed. See the Maven error above.'
        case 'Image':
            return '`docker build` failed. See the docker error above (is the jar in target/, is the docker daemon reachable?).'
        case 'Deploy':
            return 'The new container did not become healthy; the previous version was restored when there was one. Check the container log quoted below and that the database is running (docker compose up -d db).'
        case 'Smoke test':
            return 'The application is up but GET /api/students did not return data. Check the database content and the container log.'
        default:
            return 'See the console log above for the first error.'
    }
}

// True when a parameter or env value is set. Password parameters are hudson.util.Secret objects (no trim()),
// so always go through toString().
def isSet(Object value) {
    return value != null && value.toString().trim().length() > 0
}

// Runs a command and keeps a copy of its output in .pipeline.log, so a failed build can quote the real error.
def logged(String cmd) {
    sh """#!/bin/bash
set -o pipefail
${cmd} 2>&1 | tee -a .pipeline.log
"""
}

def mvn(String args) {
    logged("./mvnw -B ${args}")
}

// Runs body with the secret available to sh steps (see the order in the header). The shell scripts also accept
// the *_INPUT parameter variables.
def withSonarToken(Closure body) {
    if (isSet(params.SONAR_TOKEN_INPUT) || isSet(env.SONAR_TOKEN)) {
        body()
    } else {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) { body() }
    }
}

def withDbPassword(Closure body) {
    if (isSet(params.DB_PASSWORD_INPUT) || isSet(env.DB_PASSWORD)) {
        body()
    } else {
        withCredentials([string(credentialsId: 'db-password', variable: 'DB_PASSWORD')]) { body() }
    }
}

// Where a secret comes from, for the Prerequisites report (the value is never printed).
def secretSource(Object paramValue, String paramName, Object envValue, String envName, String credentialId) {
    if (isSet(paramValue)) {
        return "build parameter ${paramName}"
    }
    if (isSet(envValue)) {
        return "global environment variable ${envName}"
    }
    def found = 'none'
    try {
        withCredentials([string(credentialsId: credentialId, variable: 'CHECK_ONLY')]) {
            found = "credential '${credentialId}'"
        }
    } catch (Exception e) {
        found = 'none'
    }
    return found
}

def isScanBranch() {
    return params.SCAN_BRANCHES.split(',').collect { it.trim() }.contains(params.BRANCH)
}

// Deploy only code that was scanned, and only when asked.
def shouldDeploy() {
    return params.DEPLOY && isScanBranch()
}

// Stage "Prerequisites": show what this build will use (secrets masked) and verify the node before the build starts.
def checkPrerequisites() {
    def willScan = isScanBranch()
    def willDeploy = shouldDeploy()

    echo '=================== PARAMETERS USED BY THIS BUILD ==================='
    for (name in params.keySet()) {
        def value = params[name]?.toString() ?: ''
        def secret = ['TOKEN', 'PASSWORD', 'SECRET'].any { name.toUpperCase().contains(it) }
        def shown = secret ? (isSet(value) ? '****** (set, masked)' : '(empty)') : (value ?: '(empty)')
        echo "${name} = ${shown}"
    }
    echo "SONAR_URL (from Jenkins) = ${env.SONAR_URL ?: '(NOT SET)'}"
    echo "JAVA_HOME                = ${env.JAVA_HOME}"
    echo "Node / workspace         = ${env.NODE_NAME} / ${env.WORKSPACE}"
    echo "SonarQube scan           = ${willScan ? 'YES' : 'NO (BRANCH is not in SCAN_BRANCHES)'}"
    echo "Deploy                   = ${willDeploy ? 'YES' : 'NO (DEPLOY is off, or the branch is not scanned)'}"

    def tokenSource = willScan ? secretSource(params.SONAR_TOKEN_INPUT, 'SONAR_TOKEN_INPUT', env.SONAR_TOKEN, 'SONAR_TOKEN', 'sonar-token') : 'not needed'
    def dbSource = willDeploy ? secretSource(params.DB_PASSWORD_INPUT, 'DB_PASSWORD_INPUT', env.DB_PASSWORD, 'DB_PASSWORD', 'db-password') : 'not needed'
    echo "Sonar token source       = ${tokenSource}"
    echo "DB password source       = ${dbSource}"

    def checks = '''#!/bin/bash
rm -f .pipeline.log
fail=0
ok()   { echo "[ OK ]   $*"; }
warn() { echo "[WARN]   $*"; }
bad()  { echo "[FAIL]   $*"; echo "[ERROR] $*" >> .pipeline.log; fail=1; }
echo "=================== PREREQUISITES ==================="
echo "commit: $(git log -1 --format='%h %s' 2>/dev/null | cut -c1-90)"

for t in bash git curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $("$t" --version 2>&1 | head -1 | cut -c1-70)"; else bad "$t is not installed on this node"; fi
done

need=$(grep -o '<java.version>[0-9]*' pom.xml 2>/dev/null | head -1 | grep -o '[0-9]*$' || true)
need=${need:-21}
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
have=$("$JAVA" -version 2>&1 | grep -o 'version "[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
if [ -n "${JAVA_HOME:-}" ] && [ ! -x "$JAVA_HOME/bin/java" ]; then
  bad "JAVA_HOME=$JAVA_HOME has no bin/java on this node. Edit JAVA_HOME in the environment block of the Jenkinsfile to the real JDK $need path (ls /usr/lib/jvm)"
elif [ -z "$have" ]; then
  bad "java not found (JAVA_HOME=${JAVA_HOME:-not set}). Install JDK $need and set JAVA_HOME in the Jenkinsfile environment block"
elif [ "$have" -lt "$need" ]; then
  bad "Java $have found at JAVA_HOME=${JAVA_HOME:-PATH} but pom.xml needs $need or newer. Point JAVA_HOME in the Jenkinsfile environment block to a JDK $need"
else
  ok "java $have (pom.xml needs $need) at JAVA_HOME=${JAVA_HOME:-from PATH}"
  if command -v "$JAVAC" >/dev/null 2>&1; then ok "javac is present (JDK, not only a JRE)"; else bad "javac is missing: this is a JRE. Install the JDK package or point JAVA_HOME at a full JDK"; fi
fi

if [ -x ./mvnw ]; then ok "mvnw is executable"; else bad "./mvnw is missing or not executable (chmod +x mvnw, then commit the mode)"; fi

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

if [ "${WILL_DEPLOY:-}" = "true" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    bad "docker is not installed on this node"
  elif ! docker info >/dev/null 2>&1; then
    bad "docker is installed but this user cannot use it. Add the jenkins user to the docker group and restart Jenkins"
  else
    ok "docker works: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if [ -n "${DOCKER_NETWORK:-}" ]; then
      if docker network inspect "$DOCKER_NETWORK" >/dev/null 2>&1; then ok "docker network '$DOCKER_NETWORK' exists"; else bad "docker network '$DOCKER_NETWORK' does not exist. Start the database first: docker compose up -d db"; fi
    fi
    rest="${DB_URL#*://}"
    dbhost="${rest%%[:/]*}"
    if docker ps --format '{{.Names}}' | grep -qx "$dbhost"; then ok "database container '$dbhost' is running"; else warn "no running container named '$dbhost': fine only when the database runs elsewhere"; fi
  fi
  if [ "${DB_SOURCE:-none}" = "none" ]; then
    bad "no DB password: set parameter DB_PASSWORD_INPUT, global env DB_PASSWORD, or credential db-password"
  fi
else
  ok "deploy is off for this build, so docker and the database are not checked"
fi

if [ "$fail" -ne 0 ]; then echo "Prerequisites FAILED: fix the [FAIL] lines above, nothing was built."; exit 1; fi
echo "All prerequisites are met."
'''
    // pass the values explicitly: on the very first build the parameters are not registered yet, so Jenkins
    // does not export them as environment variables to sh (params.X in Groovy still has the defaults)
    def shellEnv = ["WILL_SCAN=${willScan}", "WILL_DEPLOY=${willDeploy}",
                    "TOKEN_SOURCE=${tokenSource}", "DB_SOURCE=${dbSource}",
                    "DOCKER_NETWORK=${params.DOCKER_NETWORK}", "DB_URL=${params.DB_URL}"]
    withEnv(shellEnv) {
        if (willScan && tokenSource != 'none') {
            withSonarToken { sh(script: checks) }
        } else {
            sh(script: checks)
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
        string(name: 'BRANCH', defaultValue: 'rnd', description: 'Branch to check out')
        string(name: 'SONAR_PROJECT_KEY', defaultValue: 'my-project',
               description: 'SonarQube project key (the first scan creates the project)')
        string(name: 'SONAR_PROJECT_NAME', defaultValue: '',
               description: 'Display name in SonarQube (empty = same as the key)')
        string(name: 'SCAN_BRANCHES', defaultValue: 'main,master,rnd',
               description: 'Only these branches are scanned and deployed. Community Build keeps one analysis per project, so scanning another branch overwrites the previous one')
        password(name: 'SONAR_TOKEN_INPUT', defaultValue: '',
                 description: 'SonarQube token. Only if you cannot add the sonar-token credential or a global SONAR_TOKEN (empty = use those)')
        booleanParam(name: 'DEPLOY', defaultValue: true,
                     description: 'Build the image and (re)start the application container after a green scan')
        string(name: 'IMAGE_NAME', defaultValue: 'sonarcube',
               description: 'Docker image and container name of the application')
        string(name: 'APP_PORT', defaultValue: '8081',
               description: 'Host port (127.0.0.1) of the application. 8080 is usually Jenkins itself')
        string(name: 'DB_URL', defaultValue: 'jdbc:postgresql://sonarcube-db:5432/sonarcube',
               description: 'JDBC URL the application uses. The database is NOT started by this pipeline (docker compose up -d db)')
        string(name: 'DB_USER', defaultValue: 'sonarcube', description: 'Database user of the application')
        password(name: 'DB_PASSWORD_INPUT', defaultValue: '',
                 description: 'Database password. Only if you cannot add the db-password credential or a global DB_PASSWORD (empty = use those)')
        string(name: 'DOCKER_NETWORK', defaultValue: 'sonarcube-net',
               description: 'Docker network shared with the database container (empty = default bridge, for a database reachable by host name)')
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: '',
               description: 'Jenkins credential id for a private repository (empty = anonymous)')
    }
    environment {
        SONAR_PROJECT_KEY  = "${params.SONAR_PROJECT_KEY}"
        SONAR_PROJECT_NAME = "${params.SONAR_PROJECT_NAME}"
        // The JDK of the node that runs this build. Edit this path to match your server (ls /usr/lib/jvm).
        // The Java version the project needs is read from <java.version> in pom.xml and checked in Prerequisites.
        JAVA_HOME          = "/usr/lib/jvm/java-21-openjdk"
        PATH               = "${env.JAVA_HOME}/bin:${env.PATH}"
    }
    stages {
        stage('Checkout') {
            steps {
                script {
                    if (!params.REPO_URL?.trim() || !params.BRANCH?.trim()) {
                        error 'REPO_URL and BRANCH must not be empty'
                    }
                }
                // trim: a leading space pasted into the URL gives "fatal: protocol ' https' is not supported"
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "refs/heads/${params.BRANCH.trim()}"]],
                    userRemoteConfigs: [[url: params.REPO_URL.trim(), credentialsId: params.GIT_CREDENTIALS_ID]],
                    extensions: [[$class: 'CleanBeforeCheckout']]
                ])
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Prerequisites') {
            steps { script { checkPrerequisites() } }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Test') {
            steps {
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
            when { expression { isScanBranch() } }
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
        stage('Image') {
            when { expression { shouldDeploy() } }
            steps {
                // the image is tagged with the build number (kept for rollback) and latest; it stays in the local docker
                script {
                    logged("docker build -t ${params.IMAGE_NAME}:${env.BUILD_NUMBER} -t ${params.IMAGE_NAME}:latest .")
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Deploy') {
            when { expression { shouldDeploy() } }
            steps {
                // only the application: stop the old container if it runs, start the new image, wait until healthy
                script {
                    def deployEnv = ["IMAGE_NAME=${params.IMAGE_NAME}", "APP_PORT=${params.APP_PORT}",
                                     "DB_URL=${params.DB_URL}", "DB_USER=${params.DB_USER}",
                                     "DOCKER_NETWORK=${params.DOCKER_NETWORK}"]
                    withEnv(deployEnv) {
                        withDbPassword {
                            sh '''#!/bin/bash
set -eu -o pipefail
DB_PASSWORD="${DB_PASSWORD_INPUT:-${DB_PASSWORD:-}}"
: "${DB_PASSWORD:?no DB password: set parameter DB_PASSWORD_INPUT, global env DB_PASSWORD or credential db-password}"
export DB_PASSWORD
./scripts/deploy.sh "$BUILD_NUMBER" 2>&1 | tee -a .pipeline.log
'''
                        }
                    }
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Smoke test') {
            when { expression { shouldDeploy() } }
            steps {
                script {
                    withEnv(["IMAGE_NAME=${params.IMAGE_NAME}"]) { logged('./scripts/smoke-test.sh') }
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
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
