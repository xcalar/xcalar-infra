#!/bin/bash
# This script merges the LV at /home into the LV at / after backing
# up /home/* to /root/home, then restoring it once the LVs have merged.
#
# By default (unless LV_HOME/LV_ROOT are specified) will only work on CentOS7
# default LVM installs due the default names we look for (/dev/centos/{home,root})
set -ex

LV_HOME="${LV_ROOT:-/dev/centos/home}"
LV_ROOT="${LV_ROOT:-/dev/centos/root}"

die () {
    echo >&2 "$*"
    exit 1
}

if ! mountpoint -q /home; then
    die "/home is not a mountpoint"
fi

if [ "`id -u`" != "0" ]; then
    die "Must run as root"
fi

if ! lvdisplay "$LV_ROOT"; then
    die "$LV_ROOT doesn't exist, please set LV_ROOT before running this script"
fi

if ! lvdisplay "$LV_HOME"; then
    die "$LV_HOME doesn't exist, please set LV_HOME before running this script"
fi

if test -e /root/home; then
    die "/root/home exists. Please remove before running this script"
fi

if ! umount /home; then
    die "/home is in user! Try fuser -vm /home"
fi

mount /home

cp -a /home /root

if ! umount /home; then
    die "/home is in user! Try fuser -vm /home"
fi

lvremove "$LV_HOME"
cp /etc/fstab /etc/fstab.$$
#sed -Ee '\|'$LV_HOME'|d' /etc/fstab

sed -Ee '/\s+\/home\s+/ s/^#*/#/' /etc/fstab.$$ > /etc/fstab

lvextend -l +100%FREE -r "$LV_ROOT"

for ii in $(ls -d /root/home/*); do
    cp -a "$ii" /home
done
