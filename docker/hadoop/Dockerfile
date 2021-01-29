FROM sequenceiq/hadoop-docker:2.7.1
MAINTAINER Xcalar, Inc <info@xcalar.com>

ENV HADOOP_PREFIX /usr/local/hadoop
WORKDIR $HADOOP_PREFIX

RUN rm -f lib/native/*
RUN curl -sSL http://repo.xcalar.net/deps/hadoop-native-64-2.7.1.tar | tar xf - -C lib/native
RUN rpm --rebuilddb && yum makecache fast && yum install -y snappy openssl-devel krb5-workstation sssd-krb5 samba4-winbind-krb5-locator

ENV JDK_VERSION 8u144

RUN rpm --rebuilddb && rpm -Uvh http://repo.xcalar.net/deps/jdk-${JDK_VERSION}-linux-x64.rpm
ENV JAVA_HOME /usr/java/default
ENV PATH $HADOOP_PREFIX/sbin:$HADOOP_PREFIX/bin:$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN curl -sSL http://repo.xcalar.net/data/qa-1.tar.gz | tar zxf - -C /tmp && \
    /etc/bootstrap.sh && \
    until hadoop fs -mkdir /datasets; do sleep 10; done && \
    hadoop fs -copyFromLocal /tmp/qa /datasets/ && \
    hdfs dfs -mkdir /exports && \
    hdfs dfs -chmod -R +w /exports && \
    rm -rf /tmp/qa && \
    source $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh && \
    stop-yarn.sh && \
    stop-dfs.sh
RUN find $HADOOP_PREFIX/logs/ -type f | xargs rm -fv
ADD bootstrap.sh /etc/
