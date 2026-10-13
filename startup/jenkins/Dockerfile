FROM jenkins/jenkins:lts-jdk21

# The base image has JDK 21, git and curl. Maven comes from the project's ./mvnw.
# The pipeline builds and runs the application image on the host's docker through the mounted socket, so this
# image needs only the docker CLI (a static binary), not a docker daemon.
USER root
ARG DOCKER_VERSION=28.3.2
RUN curl -fsSL "https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_VERSION}.tgz" \
      | tar -xz --strip-components=1 -C /usr/local/bin docker/docker \
 && docker --version

# The Jenkinsfile sets JAVA_HOME=/usr/lib/jvm/java-21-openjdk (the usual path on RHEL-like servers). Give this image
# the same path so the same Jenkinsfile runs here unchanged.
RUN mkdir -p /usr/lib/jvm && ln -s /opt/java/openjdk /usr/lib/jvm/java-21-openjdk
USER jenkins

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

# Jenkins Configuration as Code: users, credentials and the pipeline job exist on first boot.
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
