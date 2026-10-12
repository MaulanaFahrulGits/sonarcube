// Reusable pipeline template for a Java + Maven wrapper project:
//   checkout BRANCH -> test -> lint -> SonarQube scan + quality gate -> build
// Everything project-specific is a build parameter, so one job can build any repo:
//   REPO_URL, BRANCH, SONAR_PROJECT_KEY, SONAR_PROJECT_NAME.
// The target project's pom needs the Checkstyle and JaCoCo plugins configured like this repo's pom.xml.
//
// Provided by the Jenkins image (jenkins/casc.yaml): env SONAR_URL, credential "sonar-token".
// No Docker agent and no SonarQube webhook: the scan polls for the gate (sonar.qualitygate.wait),
// so it also works when SonarQube cannot reach this Jenkins.
pipeline {
    agent any
    options {
        skipDefaultCheckout(true) // the job's SCM holds only this file; the project is checked out below
        timestamps()
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
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: '',
               description: 'Jenkins credential id for a private repository (empty = anonymous)')
        string(name: 'NOTIFY_EMAIL', defaultValue: '',
               description: 'Mail this address on failure (needs SMTP in Manage Jenkins; empty = no mail)')
    }
    environment {
        SONAR_PROJECT_KEY  = "${params.SONAR_PROJECT_KEY}"
        SONAR_PROJECT_NAME = "${params.SONAR_PROJECT_NAME}"
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
        }
        stage('Test') {
            steps {
                // lint is bound to Maven's validate phase, so skip it here; it has its own stage below
                sh './mvnw -B -Dcheckstyle.skip=true test jacoco:report'
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' }
            }
        }
        stage('Lint') {
            steps { sh './mvnw -B checkstyle:check' }
        }
        stage('SonarQube scan') {
            when {
                expression {
                    params.SCAN_BRANCHES.split(',').collect { it.trim() }.contains(params.BRANCH)
                }
            }
            steps {
                // the scanner reads the token from env SONAR_TOKEN, so it never appears on a command line
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh '''#!/bin/bash
set -eu
: "${SONAR_URL:?SONAR_URL is not set on this Jenkins (see jenkins/casc.yaml)}"
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
        stage('Build') {
            steps {
                sh './mvnw -B -DskipTests -Dcheckstyle.skip=true package'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true, allowEmptyArchive: true
            }
        }
        // stage('Deploy') { gcloud run deploy ... }  <- only reached when the gate is green
    }
    post {
        failure {
            script {
                if (params.NOTIFY_EMAIL?.trim()) {
                    try {
                        mail to: params.NOTIFY_EMAIL,
                             subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                             body: "Build or quality gate failed.\n${env.BUILD_URL}"
                    } catch (Exception e) {
                        echo "Mail not sent (is SMTP configured?): ${e.message}"
                    }
                }
                if (env.CHAT_WEBHOOK_URL?.trim()) { // Slack and Google Chat both accept {"text": ...}
                    // shebang keeps the shell from echoing the webhook URL into the log
                    sh '''#!/bin/bash
curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\\"text\\":\\"FAILED $JOB_NAME #$BUILD_NUMBER $BUILD_URL\\"}" "$CHAT_WEBHOOK_URL" || true
'''
                }
            }
        }
    }
}
