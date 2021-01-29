#!/bin/bash

set -ex

PUPPET_TAR="${PUPPET_TAR:-puppet.tar.gz}"
ENVIRONMENT=${ENVIRONMENT:-production}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --puppet-archive | -p)
            PUPPET_TAR="$1"
            shift
            ;;
        --hostname)
            MYHOSTNAME="$1"
            shift
            ;;
        --role)
            export FACTER_role="$1"
            shift
            ;;
        --cluster)
            export FACTER_cluster="$1"
            shift
            ;;
        --datacenter)
            export FACTER_datacenter="$1"
            shift
            ;;
        --environment)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            echo >&2 "ERROR: Unrecognized command $cmd"
            exit 1
            ;;
    esac
done

export PATH=/opt/puppetlabs/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:$HOME/bin

if ! test -r "$PUPPET_TAR"; then
    echo >&2 "ERROR: Unable to find $PUPPET_TAR"
    exit 1
fi

if ! test -e /etc/system-release; then
    echo >&2 "ERROR: This script is only for EL systems"
    exit 1
fi
ELVERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
ELVERSION=${ELVERSION:0:1}

if ! rpm -q puppet-agent; then
    yum install -y http://yum.puppetlabs.com/puppet6-release-el-${ELVERSION}.noarch.rpm
    yum install -y puppet-agent
fi

if [ -n "$MYHOSTNAME" ]; then
    hostnamectl set-hostname $MYHOSTNAME || true
    export HOSTNAME=$MYHOSTNAME
fi
cat <<EOF >>/etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

if [ -n "$CACHER_IP" ]; then
    echo >>/etc/hosts
    echo "$CACHER_IP  cacher  # run-puppet" | tee -a /etc/hosts
    echo "proxy = http://${CACHER_IP}:3128" | tee -a /etc/yum.conf
fi

PUPPETROOT=/etc/puppetlabs/code/environments/${ENVIRONMENT}

rm -rfv $PUPPETROOT
mkdir -p $PUPPETROOT
tar xzf ${PUPPET_TAR} -C $PUPPETROOT
cd $PUPPETROOT
set +e
(
    mkdir -p /etc/facter/facts.d
    cd /etc/facter/facts.d
    [ "${FACTER_role}x" != "x" ] && echo "role=${FACTER_role}" >role.txt
    [ "${FACTER_cluster}x" != "x" ] && echo "cluster=${FACTER_cluster}" >cluster.txt
    [ "${FACTER_datacenter}x" != "x" ] && echo "datacenter=${FACTER_datacenter}" >datacenter.txt
    [ "${FACTER_cloud}x" != "x" ] && echo "cloud=${FACTER_cloud}" >cloud.txt
)
env
cat /etc/facter/facts.d/*

COLOR_ARG=''
if ((NOCOLOR)); then
    COLOR_ARG=--color=false
fi

for retry in 1 2 3; do
    puppet apply $COLOR_ARG -t -v ./manifests/site.pp
    rc=$?
    if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then
        rc=0
        break
    fi
done

sed -i '/run-puppet/d' /etc/hosts
sed -i '/nameserver 8.8/d' /etc/resolv.conf
sed -i '\@^proxy = http://'${CACHER_IP}':3128@d' /etc/yum.conf

if [ $rc -ne 0 ]; then
    echo >&2 "ERROR($rc): Puppet failed to run"
    exit $rc
fi

exit 0
