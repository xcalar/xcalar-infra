#!/bin/bash

if [ `id -u` -ne 0 ]; then
    echo >&2 "Must run as root"
    exit 1
fi

set -e
HOSTNAME_F="$(hostname -f 2>/dev/null)"
HOSTNAME_S="$(hostname -s 2>/dev/null)"
HOSTNAME="$(hostname 2>/dev/null)"
DNSDOMAIN="$(dnsdomainname)"
if [ "$HOSTNAME" != "" ] && [ "$HOSTNAME_F" != "" ] && [ "$HOSTNAME_S" != "" ] && [ "$HOSTNAME_S" != localhost ] && [ "$HOSTNAME_F" != "$HOSTNAME_S" ]; then
    echo "Hostname configured properly"
elif test -n "$1"; then
	echo "Setting hostname to $1"
	HOSTNAME="${1%%.*}"
	hostname $HOSTNAME
	echo $HOSTNAME > /etc/hostname
	sed -i "/$HOSTNAME/d" /etc/hosts
	echo "127.0.1.1	${HOSTNAME_S}.${DNSDOMAIN} $HOSTNAME_S" >> /etc/hosts
    HOSTNAME_F="$(hostname -f 2>/dev/null)"
    HOSTNAME_S="$(hostname -s 2>/dev/null)"
    HOSTNAME="$(hostname 2>/dev/null)"
fi

if [[ "$HOSTNAME" =~ ^localhost ]] || test -z "$HOSTNAME" || test -z "$HOSTNAME_S" || test -z "$HOSTNAME_F"; then
	echo >&2 "Invalid hostname: HOSTNAME=$HOSTNAME, HOSTNAME_S=$HOSTNAME_S, HOSTNAME_F=$HOSTNAME_F"
	echo >&2 "Please specify a short hostname on the command line"
	exit 1
fi

set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if test -e /etc/redhat-release; then
    ELVERSION="$(grep -Eow '([0-9\.])+' /etc/system-release | cut -d'.' -f1)"
    VERSTRING=el${ELVERSION}
elif test -f /etc/os-release; then
    . /etc/os-release
    VERSION="$(echo $VERSION_ID | cut -d'.' -f1)"
    case "$ID" in
        ubuntu)
            VERSTRING=ub${VERSION}
            case "$VERSION" in
                14) CODENAME=trusty;;
                16) CODENAME=xenial;;
            esac
            ;;
        rhel|ol|centos)
            ELVERSION=${VERSION}
            VERSTRING=el${VERSION}
            ;;
    esac
fi

if test -n "$ELVERSION"; then
    REPOPKG=puppetlabs-release-pc1-el-${ELVERSION}.noarch.rpm
    curl -fsSL http://yum.puppetlabs.com/$REPOPKG > /tmp/$REPOPKG
    yum localinstall -y /tmp/$REPOPKG
    yum clean all
    yum makecache fast
    yum install -y puppet-agent
elif test -n "$CODENAME"; then
    REPOPKG=puppetlabs-release-pc1-${CODENAME}.deb
    curl -fsSL http://apt.puppetlabs.com/$REPOPKG > /tmp/$REPOPKG
    dpkg -i /tmp/$REPOPKG
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq puppet-agent
else
    echo >&2 "Unrecognized OS version. Please set VERSTRING to el6, el7 or ub14 before running this script"
    for release_file in `ls /etc/*-release`; do
        echo "#=== $release_file ==="
        cat $release_file
    done
    exit 1
fi

export PATH=/opt/puppetlabs/bin:$PATH
