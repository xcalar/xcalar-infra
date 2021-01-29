#!/bin/bash
set -ex

setenforce 0
sed --follow-symlinks -i 's/^SELINUX=.*$/SELINUX=disabled/g' /etc/sysconfig/selinux

curl -sSL http://repo.xcalar.net/builds/prod/xcalar-1.0.3.17-607.db0c4140-installer > /tmp/xcalar-install
bash /tmp/xcalar-install --noStart
rm -f /tmp/xcalar-install
cat /etc/sysctl.d/90-xcsysctl.conf >> /etc/sysctl.conf
cat /etc/security/limits.d/90-xclimits.conf >> /etc/security/limits.conf
yum remove -y xcalar
yum install -y collectd htop gdb
systemctl disable httpd.service
systemctl disable firewalld.service || true
systemctl disable puppet.service || true
rm -rf /opt/xcalar /var/opt/xcalar /etc/xcalar/
