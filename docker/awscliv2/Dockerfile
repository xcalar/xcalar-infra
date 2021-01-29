FROM centos:7

RUN yum install -y curl ca-certificates groff \
    && yum clean all \
    && rm -rvf /var/cache/yum/*

ADD packer/scripts/awscliv2.sh /usr/bin/

RUN bash -x awscliv2.sh

CMD ["/usr/bin/aws"]
