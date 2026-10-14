// CI/CD for a Java + Maven project that ships as a Docker image.
//
//   Checkout -> Prerequisites -> Test -> Lint -> SonarQube scan + gate -> Build -> Image -> Deploy -> Smoke test
//
// Reading guide: this file only describes WHAT happens and in which order. The shell logic lives in scripts/
// (prerequisites.sh, sonar-gate.sh, sonar-scan.sh, deploy.sh, smoke-test.sh), so each piece can also be run by hand.
//
// Like a real project, the pipeline only brings up the APPLICATION. The database is separate infrastructure
// (startup/docker-compose.yml); the app container just connects to it.
//
// Needs on the Jenkins node: plugins Pipeline, Git, Credentials Binding; the JDK in JAVA_HOME below; git, curl;
// docker usable by the Jenkins user (for Image/Deploy). Needs from Jenkins: env SONAR_URL and a Sonar token.
// The Sonar token comes from the first of: parameter SONAR_TOKEN_INPUT, global env SONAR_TOKEN, credential "sonar-token".
// The database login is read from the running database container; set global env DB_PASSWORD (or credential
// "db-password") only when the database is not a local container.
//
// On failure there is no mail or chat message: the end of the console log says which stage failed and why.

// ---------------------------------------------------------------- helpers
// True when a value is set. Password parameters are hudson.util.Secret objects (no trim()), so use toString().
def isSet(Object value) {
    return value != null && value.toString().trim().length() > 0
}

// Runs a command and keeps its output in .pipeline.log, so the final failure block can quote the real error.
def logged(String cmd) {
    sh """#!/bin/bash
set -o pipefail
${cmd} 2>&1 | tee -a .pipeline.log
"""
}

def mvn(String args) {
    logged("./mvnw -B ${args}")
}

def isScanBranch() {
    return params.SCAN_BRANCHES.split(',').collect { it.trim() }.contains(params.BRANCH)
}

// Image, Deploy and Smoke test run only for code that was scanned (so it passed the gate).
def shouldDeploy() {
    return params.DEPLOY && isScanBranch()
}

// Where a secret comes from, for the report (the value is never printed): parameter, global env, or credential.
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

// Runs body with SONAR_TOKEN available to sh steps (the scripts also accept SONAR_TOKEN_INPUT).
def withSonarToken(Closure body) {
    if (isSet(params.SONAR_TOKEN_INPUT) || isSet(env.SONAR_TOKEN)) {
        body()
    } else {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) { body() }
    }
}

// Runs body, binding credential "db-password" only when it exists (otherwise deploy.sh reads the login
// from the database container).
def withDbPassword(Closure body) {
    def source = secretSource(null, '', env.DB_PASSWORD, 'DB_PASSWORD', 'db-password')
    if (source.startsWith('credential')) {
        withCredentials([string(credentialsId: 'db-password', variable: 'DB_PASSWORD')]) { body() }
    } else {
        body()
    }
}

// ---------------------------------------------------------------- stage helpers
// Each stage ends with `post { failure { script { markFailed() } } }`: in the final post block Jenkins reports the
// stage name as "Declarative: Post Actions", so the failed stage has to be remembered when it fails.
def markFailed() {
    env.FAILED_STAGE = env.STAGE_NAME
}

// Stage "Prerequisites": show what this build will use (secrets masked), then run scripts/prerequisites.sh.
def checkPrerequisites() {
    def willScan = isScanBranch()
    def willDeploy = shouldDeploy()

    echo '=================== PARAMETERS USED BY THIS BUILD ==================='
    for (name in params.keySet()) {
        def value = params[name]?.toString() ?: ''
        def secret = ['TOKEN', 'PASSWORD', 'SECRET'].any { name.toUpperCase().contains(it) }
        echo "${name} = ${secret ? (isSet(value) ? '****** (set, masked)' : '(empty)') : (value ?: '(empty)')}"
    }
    def tokenSource = willScan ? secretSource(params.SONAR_TOKEN_INPUT, 'SONAR_TOKEN_INPUT', env.SONAR_TOKEN, 'SONAR_TOKEN', 'sonar-token') : 'not needed'
    def dbSource = willDeploy ? secretSource(null, '', env.DB_PASSWORD, 'DB_PASSWORD', 'db-password') : 'not needed'
    echo "SONAR_URL (from Jenkins) = ${env.SONAR_URL ?: '(NOT SET)'}"
    echo "JAVA_HOME                = ${env.JAVA_HOME}"
    echo "Sonar scan / deploy      = ${willScan ? 'YES' : 'NO (BRANCH is not in SCAN_BRANCHES)'} / ${willDeploy ? 'YES' : 'NO'}"
    echo "Sonar token source       = ${tokenSource}"
    echo "Database login           = ${dbSource == 'none' ? 'read from the database container' : dbSource}"

    // Passed explicitly: on the very first build the parameters are not registered yet, so Jenkins would not
    // export them as environment variables to sh (params.X in Groovy still has the defaults).
    def scriptEnv = ["WILL_SCAN=${willScan}", "WILL_DEPLOY=${willDeploy}", "TOKEN_SOURCE=${tokenSource}",
                     "DB_SOURCE=${dbSource}", "DB_URL=${params.DB_URL}", "DOCKER_NETWORK=${params.DOCKER_NETWORK}"]
    withEnv(scriptEnv) {
        if (willScan && tokenSource != 'none') {
            withSonarToken { sh 'scripts/prerequisites.sh' }
        } else {
            sh 'scripts/prerequisites.sh'
        }
    }
}

// One line per stage, printed at the end of a failed build.
def failureHint(String stageName) {
    def hints = [
        'Checkout'      : 'Cannot clone REPO_URL at BRANCH. Check the URL, the branch name, and GIT_CREDENTIALS_ID for a private repo.',
        'Prerequisites' : 'The environment is not ready. Each problem is a [FAIL] line in the Prerequisites output. If there is none, the Jenkinsfile itself threw: read the exception printed after "Also:".',
        'Test'          : 'A unit test failed or the code does not compile. Surefire lists each failing test (search the log for FAILURE or ERROR).',
        'Lint'          : 'Checkstyle found violations, listed above as file:line: message.',
        'SonarQube scan': 'The gate could not be assigned, the scanner failed, or the quality gate is red. The red conditions are listed below when available.',
        'Build'         : 'Packaging failed. See the Maven error above.',
        'Image'         : '`docker build` failed. Is the jar in target/ and the docker daemon reachable?',
        'Deploy'        : 'The new container did not become healthy; the previous version was restored when there was one. Check the container log quoted below and that the database runs.',
        'Smoke test'    : 'The application is up but GET /api/students did not return data. Check the database content and the container log.',
    ]
    return hints[stageName] ?: 'See the console log above for the first error.'
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
                echo "Quality gate status is ${status.status}, so the scan itself failed: read the error above."
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

// ---------------------------------------------------------------- pipeline
pipeline {
    agent any
    options {
        skipDefaultCheckout(true) // the job's SCM holds only this file; the project is checked out below
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }
    parameters {
        // what to build
        string(name: 'REPO_URL', defaultValue: 'https://github.com/MaulanaFahrulGits/sonarcube.git', description: 'Git repository to build')
        string(name: 'BRANCH', defaultValue: 'rnd', description: 'Branch to check out')
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: '', description: 'Jenkins credential id for a private repository (empty = anonymous)')
        // SonarQube
        string(name: 'SONAR_PROJECT_KEY', defaultValue: 'my-project', description: 'SonarQube project key (the project is created when it does not exist)')
        string(name: 'SONAR_PROJECT_NAME', defaultValue: '', description: 'Name shown on the SonarQube dashboard (empty = the project key)')
        string(name: 'SONAR_QUALITY_GATE', defaultValue: 'rnd-strict', description: 'Quality gate assigned to the project before the scan; created with strict conditions if it does not exist (empty = keep what the server has)')
        string(name: 'SCAN_BRANCHES', defaultValue: 'main,master,rnd', description: 'Only these branches are scanned and deployed. Community Build keeps one analysis per project, so another branch overwrites the previous analysis')
        password(name: 'SONAR_TOKEN_INPUT', defaultValue: '', description: 'SonarQube token, only if there is no credential sonar-token or global SONAR_TOKEN (empty = use those)')
        // deploy (the application only; the database is not started by this pipeline)
        booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Build the image and (re)start the application container after a green scan')
        string(name: 'IMAGE_NAME', defaultValue: 'sonarcube', description: 'Docker image and container name of the application')
        string(name: 'APP_PORT', defaultValue: '8081', description: 'Host port (127.0.0.1) of the application. 8080 is usually Jenkins itself')
        string(name: 'DB_URL', defaultValue: 'jdbc:postgresql://sonarcube-db:5432/sonarcube', description: 'JDBC URL of the database. The login is read from that container')
        string(name: 'DOCKER_NETWORK', defaultValue: 'sonarcube-net', description: 'Docker network shared with the database container (empty = default bridge)')
    }
    environment {
        SONAR_PROJECT_KEY  = "${params.SONAR_PROJECT_KEY}"
        SONAR_PROJECT_NAME = "${params.SONAR_PROJECT_NAME}"
        SONAR_QUALITY_GATE = "${params.SONAR_QUALITY_GATE}"
        // The JDK of the node that runs this build: edit the path for your server (ls /usr/lib/jvm).
        // The Java version itself is read from <java.version> in pom.xml and checked in Prerequisites.
        JAVA_HOME          = "/usr/lib/jvm/java-21-openjdk"
        PATH               = "${env.JAVA_HOME}/bin:${env.PATH}"
    }
    stages {
        stage('Checkout') {
            steps {
                // trim: a leading space pasted into the URL gives "fatal: protocol ' https' is not supported"
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "refs/heads/${params.BRANCH.trim()}"]],
                    userRemoteConfigs: [[url: params.REPO_URL.trim(), credentialsId: params.GIT_CREDENTIALS_ID]],
                    extensions: [[$class: 'CleanBeforeCheckout']]
                ])
            }
            post { failure { script { markFailed() } } }
        }
        stage('Prerequisites') {
            steps { script { checkPrerequisites() } }
            post { failure { script { markFailed() } } }
        }
        stage('Test') {
            // lint is bound to Maven's validate phase, so skip it here; it has its own stage below
            steps { script { mvn '-Dcheckstyle.skip=true test jacoco:report' } }
            post { failure { script { markFailed() } } }
        }
        stage('Lint') {
            steps { script { mvn 'checkstyle:check' } }
            post { failure { script { markFailed() } } }
        }
        stage('SonarQube scan') {
            when { expression { isScanBranch() } }
            steps {
                script { withSonarToken { logged('scripts/sonar-scan.sh') } }
            }
            post { failure { script { markFailed() } } }
        }
        stage('Build') {
            steps {
                script { mvn '-DskipTests -Dcheckstyle.skip=true package' }
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: true
            }
            post { failure { script { markFailed() } } }
        }
        stage('Image') {
            when { expression { shouldDeploy() } }
            steps {
                // tagged with the build number (kept for rollback) and latest; stays in the local docker, no registry
                script { logged("docker build -t ${params.IMAGE_NAME}:${env.BUILD_NUMBER} -t ${params.IMAGE_NAME}:latest .") }
            }
            post { failure { script { markFailed() } } }
        }
        stage('Deploy') {
            when { expression { shouldDeploy() } }
            steps {
                // only the application: stop the old container if it runs, start the new image, wait until healthy
                script {
                    def deployEnv = ["IMAGE_NAME=${params.IMAGE_NAME}", "APP_PORT=${params.APP_PORT}",
                                     "DB_URL=${params.DB_URL}", "DOCKER_NETWORK=${params.DOCKER_NETWORK}"]
                    withEnv(deployEnv) {
                        withDbPassword { logged("scripts/deploy.sh ${env.BUILD_NUMBER}") }
                    }
                }
            }
            post { failure { script { markFailed() } } }
        }
        stage('Smoke test') {
            when { expression { shouldDeploy() } }
            steps {
                script { withEnv(["IMAGE_NAME=${params.IMAGE_NAME}"]) { logged('scripts/smoke-test.sh') } }
            }
            post { failure { script { markFailed() } } }
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
