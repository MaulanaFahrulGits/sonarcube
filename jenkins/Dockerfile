FROM jenkins/jenkins:lts-jdk21

# The base image already has JDK 21, git and curl. Maven comes from the project's ./mvnw,
# so builds need no Docker socket and no sibling containers.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# Jenkins Configuration as Code: users, the SonarQube credential and the pipeline job exist on first boot.
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
