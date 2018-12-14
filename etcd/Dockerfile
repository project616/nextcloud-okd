#
# ETCD Custom Container
#
FROM centos:latest
MAINTAINER Marco Caimi <marco.caimi@fastweb.it>

# Install prerequisites
RUN yum install -y iproute which sharutils
# Install etcd
RUN yum install -y etcd

# Copy scripts
ADD check_etcd.sh /tmp/check_etcd.sh 
RUN chmod +x /tmp/check_etcd.sh
ADD run.sh /tmp/run.sh 
RUN chmod +x /tmp/run.sh

# Service ports
EXPOSE 2379
EXPOSE 2380

# Data Volumes
RUN mkdir -p /var/lib/state.etcd
VOLUME /var/lib/state.etcd

# Run update on container derivation
ONBUILD RUN yum update -y

# Docker Healthcheck. This is the same script that is run by kubernetes
HEALTHCHECK --retries=15 --interval=60s --timeout=30s\
  CMD /tmp/check_etcd.sh -l || exit 1

# Entrypoint
ENTRYPOINT /tmp/run.sh

