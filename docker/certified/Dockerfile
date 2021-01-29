FROM ubuntu:trusty

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y -qq --no-install-recommends curl git build-essential ruby ruby-dev bundler
RUN git clone https://github.com/rcrowley/certified.git /usr/src/certified
RUN cd /usr/src/certified && make install
WORKDIR /var/lib/certified
CMD ["/bin/bash"]
