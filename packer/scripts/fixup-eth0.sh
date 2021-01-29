#!/bin/bash

die () {
    echo >&2 "$1"
    exit 1
}

if ! test -e /etc/system-release; then
    die "This script is only for EL Operating Systems!" 2
fi

RELEASE=$(rpm -qf /etc/system-release --qf '%{NAME}')
VERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
case "$RELEASE" in
    centos* | oracle* | redhat*)
        ELVERSION="${VERSION:0:1}"
        OSID="el${ELVERSION}"
        ;;
    system*)
        if [ "$VERSION" = 2 ]; then
            ELVERSION=7
            OSID="amzn2"
        else
            ELVERSION=6
            OSID="amzn1"
        fi
        ;;
    *) die "Unknown OS: ${RELEASE} ${VERSION}" ;;
esac

case "$ELVERSION" in
    6) INIT=init ;;
    7) INIT=systemd ;;
    *) die "Shouldn't have gotten here: ${RELEASE} ${VERSION} ${ELRELEASE} ${ELVERSION}" ;;
esac

cat >/etc/sysconfig/network <<EOF
NETWORKING=yes
NOZEROCONF=yes
ONBOOT=yes
EOF

sed -r -i '/(HWADDR|UUID|IPADDR|NETWORK|NETMASK|USERCTL)/d' /etc/sysconfig/network-scripts/ifcfg-e*
rm -f /etc/sysconfig/network-scripts/ifcfg-e*

cat >/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE="eth0"
NAME="eth0"
ONBOOT="yes"
IPV6INIT="yes"
BOOTPROTO="dhcp"
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
DEFROUTE="yes"
IPV4_FAILURE_FATAL="no"
IPV6_AUTOCONF="yes"
IPV6_DEFROUTE="yes"
IPV6_FAILURE_FATAL="no"
NM_CONTROLLED="no"
EOF

echo 'RUN_FIRSTBOOT=NO' >/etc/sysconfig/firstboot

rm -f /etc/udev/rules.d/70-persistent-net.rules
ln -sfn /dev/null /etc/udev/rules.d/80-net-name-slot.rules

if [ $ELVERSION = 7 ]; then
    sed -i 's/^GRUB_TIMEOUT=.*$/GRUB_TIMEOUT=0/g' /etc/default/grub
    sed -i 's/rhgb quiet/net.ifnames=0 biosdevname=0/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    if [ -d /boot/efi/EFI/redhat ]; then
        grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
    fi
    dracut --no-hostonly --force
fi
