FROM centos:7

MAINTAINER Xcalar Inc. <support@xcalar.com>

ENV LANG=en_US.UTF-8

RUN localedef -i en_US -f UTF-8 en_US.UTF-8

ADD ./docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 443 5000 8000 8443 9090 8889 12124 18552

# -------- #
#   Run!   #
# -------- #

ENTRYPOINT ["/docker-entrypoint.sh"]

