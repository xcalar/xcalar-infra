#!/bin/bash

set -x

while pgrep -af dracut; do
    sleep 1
done

cleanup() {
    if command -v yum >/dev/null; then
        yum clean all --enablerepo='*'
        rm -rfv /var/cache/yum/* /var/tmp/yum*
    fi

    sed -i '/^proxy/d' /etc/yum.conf
    echo "CHECKPOINT_DISABLE=1" | tee -a /etc/environment

    truncate -s 0 \
        /var/log/secure \
        /var/log/messages \
        /var/log/dmesg \
        /var/log/cron \
        /var/spool/mail/* \
        /var/log/audit/audit.log || true

    rm -fv /var/log/startupscript.log \
        /var/log/dmesg.old \
        /var/log/cfn-* \
        /var/log/cloud-init* \
        /var/log/user-data* \
        /var/log/boot.log* \
        /var/log/xcalar/* \
        /var/log/audit/audit.log.*

    systemctl stop systemd-journald || true
    sed -i -r 's/^#?Storage=.*$/Storage=persistent/' /etc/systemd/journald.conf
    rm -fv \
        /var/log/sa/* \
        /var/log/journal/*/* \
        /var/log/chrony/* \
        /var/log/amazon/{efs,ssm}/*

    rm -fv /etc/hostname /root/.bash_history /home/*/.bash_history
    rm -rfv /root/.pip /root/.cache /home/*/.pip /home/*/.cache
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

lsblk
df -h

cleanup

rm -rfv /tmp/* /var/tmp/*
rm -fv /etc/udev/rules.d/*-persistent-*.rules
systemd-tmpfiles --create /etc/tmpfiles.d/xcalar.conf || true
export HISTSIZE=0
export HISTFILESIZE=0
history -c

if test -e /usr/sbin/waagent; then
    echo >&2 "Running Azure deprovisioner ..."
    /usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync
fi
exit 0
