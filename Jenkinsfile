// Reusable pipeline template for a Java + Maven wrapper project:
//   checkout BRANCH -> test -> lint -> SonarQube scan + quality gate -> build
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
        case 'Checkout':
            return 'Cannot clone REPO_URL at BRANCH. Check the URL, the branch name, and GIT_CREDENTIALS_ID for a private repo.'
        case 'Test':
            return 'A unit test failed, the code does not compile, or the node has a JDK older than the project needs ("release version N not supported" or the Java check above). Surefire lists each failing test (search the log for FAILURE or ERROR).'
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

// Runs body with SONAR_TOKEN available to sh steps. The shell scripts below also accept SONAR_TOKEN_INPUT.
def withSonarToken(Closure body) {
    if (params.SONAR_TOKEN_INPUT?.trim() || env.SONAR_TOKEN?.trim()) {
        body()
    } else {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) { body() }
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
'''
                // lint is bound to Maven's validate phase, so skip it here; it has its own stage below
                sh './mvnw -B -Dcheckstyle.skip=true test jacoco:report'
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Lint') {
            steps { sh './mvnw -B checkstyle:check' }
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
set -eu
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
  -Dsonar.qualitygate.wait=true
'''
                    }
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
        stage('Build') {
            steps {
                sh './mvnw -B -DskipTests -Dcheckstyle.skip=true package'
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
