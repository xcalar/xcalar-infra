#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
INSTALL_ONLY=false
PUPPETCONF=/etc/puppetlabs/puppet/puppet.conf
CERTNAME=
SERVER=
CHECK_HOSTNAME=true

if [ $(id -u) -ne 0 ]; then
    echo >&2 "Must run as root"
    exit 1
fi

usage() {
    cat <<EOF >&2
usage: $0 [--hostname HOSTNAME] [--role ROLE] [--cluster CLUSTER] [--install-only]
	[--certname CERTNAME] [--server PUPPETSERVER] [--environment ENV]

EOF
    exit 2
}

die() {
    [ $# -gt 1 ] && rc=$1 && shift || rc=1
    echo "ERROR: $1"
    exit $rc
}

set_hostname() {
    echo >&2 "Setting hostname to $1"
    if command -v hostnamectl >/dev/null; then
        hostnamectl set-hostname "$1"
        export HOSTNAME="${1%%.*}"
    else
        export HOSTNAME="${1%%.*}"
        hostname $HOSTNAME
        echo $HOSTNAME >/etc/hostname
        sed -i "/$HOSTNAME/d" /etc/hosts
        echo "127.0.1.1	${HOSTNAME}.$(dnsdomainname) $HOSTNAME" >>/etc/hosts
        if test -e /etc/sysconfig/network; then
            sed -i "/HOSTNAME=/d" /etc/sysconfig/network
            echo "HOSTNAME=$HOSTNAME" >>/etc/sysconfig/network
        fi
    fi
}

set_fact() {
    mkdir -p /etc/facter/facts.d
    if [ -z "$2" ]; then
        rm -f /etc/facter/facts.d/${1}.txt
        return
    fi
    echo "$1=$2" >/etc/facter/facts.d/${1}.txt
}

set_puppetconf() {
    echo >&2 "Setting $1 = $2..."
    sed -i "/^${1}/d" $PUPPETCONF
    echo "$1 = $2" >>$PUPPETCONF
}

if test -e /etc/system-release; then
    ELVERSION="$(grep -Eow '([0-9\.])+' /etc/system-release | cut -d'.' -f1)"
    if [ "$ELVERSION" = 2018 ]; then
      ELVERSION=6
      OSID=amzn1
    elif [ "$ELVERSION" = 2 ]; then
      ELVERSION=7
      OSID=amzn2
    else
      OSID=el${ELVERSION}
    fi
    VERSTRING=el${ELVERSION}
elif test -f /etc/os-release; then
    . /etc/os-release
    VERSION="$(echo $VERSION_ID | cut -d'.' -f1)"
    case "$ID" in
        ubuntu)
            VERSTRING=ub${VERSION}
            case "$VERSION" in
                14) CODENAME=trusty ;;
                16) CODENAME=xenial ;;
                18) CODENAME=bionic ;;
                20) CODENAME=focal ;;
                *) die 2 "Unknown Ubuntu OS: $CODENAME";;
            esac
            ;;
        rhel | ol | centos)
            ELVERSION=${VERSION}
            VERSTRING=el${VERSION}
            ;;
    esac
else
    die 2 "Unknown operating system"
fi

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --hostname)
            set_hostname "$1"
            shift
            ;;
        --role)
            set_fact role "$1"
            shift
            ;;
        --cluster)
            set_fact cluster "$1"
            shift
            ;;
        --install-only) INSTALL_ONLY=true ;;
        --certname)
            CERTNAME="$1"
            shift
            ;;
        --server)
            SERVER="$1"
            shift
            ;;
        --environment)
            ENVIRONMENT="$1"
            shift
            ;;
        --no-check-hostname) CHECK_HOSTNAME=false ;;
        -h | --help) usage ;;
        *)
            echo >&2 "ERROR: Unknown argument: $cmd"
            exit 1
            ;;
    esac
done

if test -n "$ELVERSION"; then
    yum install -y epel-release
    yum update -y
    REPOPKG=puppet6-release-el-${ELVERSION}.noarch.rpm
    yum install -y http://yum.puppetlabs.com/$REPOPKG
    yum install -y puppet-agent
    yum clean all --enablerepo='*'
    rm -rf /var/cache/yum/*
elif test -n "$CODENAME"; then
    REPOPKG=puppet6-release-${CODENAME}.deb
    curl -fsSL http://apt.puppetlabs.com/$REPOPKG -o /tmp/$REPOPKG
    dpkg -i /tmp/$REPOPKG
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq puppet-agent
else
    echo >&2 "Unrecognized OS version. Please set VERSTRING to el6, el7 or ub14 before running this script"
    for release_file in $(ls /etc/*-release); do
        echo "#=== $release_file ==="
        cat $release_file
    done
    exit 1
fi

if [ "$INSTALL_ONLY" = true ]; then
    exit 0
fi

if $CHECK_HOSTNAME; then
    HOSTNAME_F="$(hostname -f 2>/dev/null)"
    HOSTNAME_S="$(hostname -s 2>/dev/null)"
    HOSTNAME="$(hostname 2>/dev/null)"

    if [[ $HOSTNAME =~ ^localhost ]] || test -z "$HOSTNAME" || test -z "$HOSTNAME_S" || test -z "$HOSTNAME_F" || [[ $HOSTNAME_S =~ int.xcalar.com$ ]]; then
        echo >&2 "Invalid hostname: HOSTNAME=$HOSTNAME, HOSTNAME_S=$HOSTNAME_S, HOSTNAME_F=$HOSTNAME_F"
        echo >&2 "Please specify a short hostname on the command line"
        exit 1
    fi
fi

if ! test -e $PUPPETCONF; then
    mkdir -p $(dirname $PUPPETCONF)
    touch $PUPPETCONF
fi

if ! grep -q '^\[main\]' $PUPPETCONF; then
    echo -e '\n[main]\n' >>$PUPPETCONF
fi

if [ -n "$CERTNAME" ]; then
    set_puppetconf certname "$CERTNAME"
fi
if [ -n "$SERVER" ]; then
    set_puppetconf server "$SERVER"
fi
if [ -n "$ENVIRONMENT" ]; then
    set_puppetconf environment "$ENVIRONMENT"
fi

export PATH=/opt/puppetlabs/bin:$PATH

echo >&2 "Setting puppet service to start on boot"
if test -d /run/systemd; then
    systemctl enable puppet
else
    if test -x /sbin/chkconfig; then
        chkconfig puppet on
    elif command -v update-rc.d; then
        update-rc.d puppet enable
    fi
fi

set +e
puppet agent -t --verbose --waitforcert 900 --detailed-exitcodes
rc=$?
if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then
    echo >&2 "OK! Puppet agent exited with $rc"
    rc=0
else
    echo >&2 "Puppet agent exited with $rc"
    echo >&2 "Rerunning puppet to ensure it isn't a convergence issue"
    while test -f /opt/puppetlabs/puppet/cache/state/agent_catalog_run.lock; do
        echo >&2 "Waiting for current puppet agent run to finish ..."
        sleep 5
    done
    puppet agent -t --verbose --waitforcert 900 --detailed-exitcodes
    rc=$?
    if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then
        echo >&2 "OK! Puppet agent exited with $rc"
        rc=0
    else
        echo >&2 "FAILED! Puppet agent exited with $rc"
    fi
fi

exit $rc
