FROM centos:6
MAINTAINER Amit Bakshi <ambakshi@gmail.com>

RUN yum clean all && yum update -y && yum install -y curl wget ca-certificates bash coreutils unzip
RUN yum install -y krb5-server krb5-workstation openldap-clients java-1.7.0-openjdk
WORKDIR /root
COPY UnlimitedJCEPolicyJDK7.zip /root/
RUN curl -sSL https://raw.githubusercontent.com/git4impatient/quickKerberos/master/goKerberos_beforeCM.sh > goKerberos_beforeCM.sh
RUN sed -i 's@/usr/java/jdk1.7.0_67-cloudera@/usr/lib/jvm@g' goKerberos_beforeCM.sh
RUN sed -i 's@quickstart.cloudera@127.0.0.1@g' goKerberos_beforeCM.sh
RUN mkdir -p /etc/hadoop
RUN printf '\ncloudera\ncloudera\ncloudera\n' | bash -ex goKerberos_beforeCM.sh
EXPOSE 88 88/udp
COPY start.sh /
CMD ["/start.sh"]

