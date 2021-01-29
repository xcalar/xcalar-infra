#!/bin/bash

set -x

while pgrep -af dracut; do
    sleep 10
done

cleanup() {
    if command -v yum >/dev/null; then
        yum clean all --enablerepo='*'
        rm -rfv /var/cache/yum/* /var/tmp/yum*
    fi

    sed -i '/^proxy/d' /etc/yum.conf

    truncate -s 0 \
        /var/log/secure \
        /var/log/messages \
        /var/log/dmesg \
        /var/log/cron \
        /var/log/audit/audit.log || true

    rm -fv /var/log/startupscript.log \
        /var/log/dmesg.old \
        /var/log/cfn-* \
        /var/log/cloud-init* \
        /var/log/user-data* \
        /var/log/nomad \
        /var/log/boot.log* \
        /var/log/grubby* \
        /var/log/spooler \
        /var/log/tallylog \
        /var/log/tuned/* \
        /var/log/xcalar/* \
        /var/log/audit/audit.log.*

    rm -rfv \
        /var/log/sa/* \
        /var/log/journal/* \
        /var/log/chrony/* \
        /var/log/amazon/{efs,ssm}/*

    rm -fv /etc/hostname /root/.{bash_history,pip,cache} /home/*/.{bash_history,pip,cache}
    if [[ $PACKER_BUILDER_TYPE =~ amazon ]] || [[ $PACKER_BUILDER_TYPE =~ azure ]]; then
        echo >&2 "Detected PACKER_BUILDER_TYPE=$PACKER_BUILDER_TYPE, deleting authorized_keys"
        rm -fv /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys
    fi

    rm -rfv /var/lib/cloud/instances/*

    : >/var/log/lastlog
    : >/var/log/maillog
    : >/var/log/wtmp
    : >/var/log/btmp
    : >/etc/machine-id
}

cleanup

touch /.unconfigured
rm -f /etc/udev/rules.d/*-persistent-*.rules

history -c
export HISTSIZE=0
export HISTFILESIZE=0
rm -fv /root/.bash_history /home/*/.bash_history

date -u +%FT%T%z >/etc/packer_build_time

exit 0
