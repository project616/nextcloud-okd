FROM nextcloud-base:latest
#FROM docker.io/nextcloud:13-apache

MAINTAINER Francesco Pantano <fmount@inventati.org>

RUN apt-get update && apt-get install -y sudo curl jq util-linux lsof vim-nox git python-swiftclient iputils-ping rsyslog libmcrypt4 mcrypt #libapache2-mod-security2

ADD scripts/start_nextcloud.sh /start_nextcloud.sh

# Add the patched entrypoint to take care about our
# modifications on the main nextcloud tree
ADD scripts/entrypoint.sh /entrypoint.sh

#DEBUG: Uncomment this only if you're developing locally ...
#ADD scripts/config.php /var/www/html/config/config.php
ADD scripts/ports.conf /etc/apache2/ports.conf

RUN chmod +x /start_nextcloud.sh /entrypoint.sh


ONBUILD RUN apt update

EXPOSE 8080 8443

ENTRYPOINT ["/start_nextcloud.sh"]
