FROM nginx:1.9.9
WORKDIR /tmp

# Environment variables used throughout this Dockerfile
#
# $JENKINS_STAGING  will be used to download plugins and copy config files
#                   during the Docker build process.
#
# $JENKINS_HOME     will be the final destination that Jenkins will use as its
#                   data directory. This cannot be populated before Marathon
#                   has a chance to create the host-container volume mapping.
#
ENV JENKINS_WAR_URL https://updates.jenkins-ci.org/download/war/1.658/jenkins.war
ENV JENKINS_STAGING /var/jenkins_staging
ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_FOLDER /usr/share/jenkins/
ENV JAVA_HOME "/usr/lib/jvm/java-8-oracle"

RUN apt-get update
RUN apt-get install -y git python zip curl default-jre jq apt-transport-https ca-certificates python3-pip

RUN mkdir -p /var/log/nginx/jenkins
COPY conf/nginx/nginx.conf /etc/nginx/nginx.conf

RUN mkdir -p $JENKINS_HOME
RUN mkdir -p ${JENKINS_FOLDER}/war
ADD ${JENKINS_WAR_URL} ${JENKINS_FOLDER}/jenkins.war

COPY scripts/plugin_install.sh /usr/local/jenkins/bin/plugin_install.sh
COPY scripts/bootstrap.py /usr/local/jenkins/bin/bootstrap.py

COPY conf/jenkins/config.xml "${JENKINS_STAGING}/config.xml"
COPY conf/jenkins/jenkins.model.JenkinsLocationConfiguration.xml "${JENKINS_STAGING}/jenkins.model.JenkinsLocationConfiguration.xml"
COPY conf/jenkins/nodeMonitors.xml "${JENKINS_STAGING}/nodeMonitors.xml"

RUN /usr/local/jenkins/bin/plugin_install.sh "${JENKINS_STAGING}/plugins"

# Java 8 & Docker repositories
RUN echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | tee /etc/apt/sources.list.d/webupd8team-java.list ; \
    echo "deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" | tee -a /etc/apt/sources.list.d/webupd8team-java.list ; \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys EEA14886 ; \
    echo 'oracle-java8-installer shared/accepted-oracle-license-v1-1 select true' | /usr/bin/debconf-set-selections

RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D && \
    echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' > /etc/apt/sources.list.d/docker.list

RUN apt-get update

# Mount the Docker socket from the host!
RUN apt-get install -y docker-engine=1.9.0-0~trusty oracle-java8-installer

RUN curl -o /tmp/nodeinstaller https://deb.nodesource.com/setup_4.x && bash /tmp/nodeinstaller && \
    apt-get install -y nodejs

# Override the default property for DNS lookup caching
RUN echo 'networkaddress.cache.ttl=60' >> ${JAVA_HOME}/jre/lib/security/java.security

CMD /usr/local/jenkins/bin/bootstrap.py && nginx && \
java ${JVM_OPTS}                                    \
    -Dhudson.udp=-1                                 \
    -Djava.awt.headless=true                        \
    -DhudsonDNSMultiCast.disabled=true              \
    -jar ${JENKINS_FOLDER}/jenkins.war              \
    --httpPort=${PORT1}                             \
    --webroot=${JENKINS_FOLDER}/war                 \
    --ajp13Port=-1                                  \
    --httpListenAddress=127.0.0.1                   \
    --ajp13ListenAddress=127.0.0.1                  \
    --preferredClassLoader=java.net.URLClassLoader  \
    --prefix=${JENKINS_CONTEXT}
