#!/bin/bash

: ${HADOOP_PREFIX:=/usr/local/hadoop}

$HADOOP_PREFIX/etc/hadoop/hadoop-env.sh

rm /tmp/*.pid

# installing libraries if any - (resource urls added comma separated to the ACP system variable)
cd $HADOOP_PREFIX/share/hadoop/common ; for cp in ${ACP//,/ }; do  echo == $cp; curl -LO $cp ; done; cd -

# altering the core-site configuration
sed s/HOSTNAME/$HOSTNAME/ /usr/local/hadoop/etc/hadoop/core-site.xml.template > /usr/local/hadoop/etc/hadoop/core-site.xml


service sshd start
$HADOOP_PREFIX/sbin/start-dfs.sh
$HADOOP_PREFIX/sbin/start-yarn.sh

if [[ $1 == "-t" ]]; then
    cd $HADOOP_PREFIX
    exec tail -F logs/*.log logs/*.out logs/userlogs/*
fi

if [[ $1 == "-d" ]]; then
    cd $HADOOP_PREFIX
    until false; do sleep 1000; done
fi

if [[ $1 == "-bash" ]]; then
    exec /bin/bash -l
fi
