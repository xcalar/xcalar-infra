FROM postgres:9.5.1
MAINTAINER Amit Bakshi <abakshi@xcalar.com>

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y git python-pip python-dev curl build-essential
RUN pip install -U wal-e
RUN mkdir -p /docker-entrypoint-initdb.d
ADD reviewdb.sh /docker-entrypoint-initdb.d/

