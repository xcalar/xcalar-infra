#!/bin/bash
#
# shellcheck disable=SC2164

CLEAN_ETC=1
FIX_PAM=1
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --no-clean-etc) CLEAN_ETC=0;;
        --no-fix-pam) FIX_PAM=0;;
        -*) echo >&2 "ERROR: Unknown option: $cmd"; exit 1;;
    esac
done

# As taken from https://hub.docker.com/r/centos/systemd/dockerfile
(cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == systemd-tmpfiles-setup.service ] || rm -fv $i; done); \
rm -fv /lib/systemd/system/multi-user.target.wants/*;\
rm -fv /lib/systemd/system/initrd.target.wants/*; \
rm -fv /lib/systemd/system/local-fs.target.wants/*; \
rm -fv /lib/systemd/system/sockets.target.wants/*udev*; \
rm -fv /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -fv /lib/systemd/system/basic.target.wants/*;\
rm -fv /lib/systemd/system/anaconda.target.wants/*;

if ((CLEAN_ETC)); then
    rm -fv /etc/systemd/system/*.wants/*
fi

cd /lib/systemd/system

for ii in systemd-machine-id-commit.service systemd-update-utmp-runlevel.service dracut*.service; do
    systemctl mask $ii
done
for ii in sys-fs-fuse-connections.mount tuned.service gssproxy.service proc-fs-nfsd.mount var-lib-nfs-rpc_pipefs.mount; do
    systemctl mask $ii
done

systemctl set-default multi-user.target

mkdir -p /etc/selinux/targeted/contexts
echo '<busconfig><selinux></selinux></busconfig>' > /etc/selinux/targeted/contexts/dbus_contexts

#sed -i -r 's/Defaults\s+requiretty/Defaults\t!requiretty/g' /etc/sudoers
#if test -e /etc/pam.d/sshd; then
#    sed --follow-symlinks -i -r 's@^(session\s+)required(\s+pam_loginuid.so)@\1optional\2@' /etc/pam.d/sshd
#fi
#sed --follow-symlinks -i -r 's@^(session\s+)required(\s+pam_limits.so)@\1optional\2@' /etc/pam.d/*
#sed --follow-symlinks -i -r 's@^(session\s+)include(\s+system-auth)@#\1include\2@' /etc/pam.d/su* || true
sed -r -i 's/Defaults\s+requiretty/Defaults\t!requiretty/g' /etc/sudoers
if ((FIX_PAM)); then
    sed --follow-symlinks -r -i 's@^(session\s+)([a-z]+)(\s+pam_limits.so)@#\1\2\3@' /etc/pam.d/* || true
    sed --follow-symlinks -r -i 's@^(session\s+)([a-z]+)(\s+system-auth)@#\1\2\3@' /etc/pam.d/su* || true
    if test -e /etc/pam.d/sshd; then
        sed --follow-symlinks -r -i 's@^(session\s+)([a-z]+)(\s+pam_loginuid.so)@#\1\2\3@' /etc/pam.d/sshd || true
        sed --follow-symlinks -r -i 's@^(account\s+)([a-z]+)(\s+pam_nologin.so)@#\1\2\3@' /etc/pam.d/sshd || true
    fi
fi
#
#rm -fv $(ls /etc/systemd/system/multi-user.target.wants/* |  grep -Ev '(rsyslog|ssh|crond)') || true

exit 0
