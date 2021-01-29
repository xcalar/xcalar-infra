#!/bin/bash

#set -u
#set -e

#set -o pipefail

set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if test -e /etc/default/grub; then
    sed -i -r 's@^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"@GRUB_CMDLINE_LINUX_DEFAULT="\1 ipv6.disable=1"@g' /etc/default/grub
    grub2-mkconfig -o "$(readlink -e /etc/grub2.cfg)"
fi

exit 0

#cat <<'EOF' > /etc/modprobe.d/blacklist-ipv6.conf
#options ipv6 disable=1
#alias net-pf-10 off
#alias ipv6 off
#install ipv6 /bin/true
#blacklist ipv6
#EOF
#
#cat <<'EOF' > /etc/sysctl.d/10-disable-ipv6.conf
#net.ipv6.conf.all.disable_ipv6 = 1
#net.ipv6.conf.default.disable_ipv6 = 1
#net.ipv6.conf.lo.disable_ipv6 = 1
#EOF
#
#chown root: /etc/modprobe.d/blacklist-ipv6.conf \
#            /etc/sysctl.d/10-disable-ipv6.conf
#
#cat /etc/sysctl.conf /etc/sysctl.d/*.conf | sysctl -e -p -
