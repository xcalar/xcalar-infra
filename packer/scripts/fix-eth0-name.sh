#!/bin/bash


if ! test -e /etc/redhat-release; then
    echo >&2 "Skipping $0, as it is not an EL distro"
    exit 0
fi

RELEASE=$(rpm -qf /etc/redhat-release)
ELVERSION=$(rpm -q $RELEASE --queryformat '%{VERSION}\n')
if [[ $ELVERSION =~ ^7 ]]; then

    cat > ${ROOTFS}/etc/default/grub << END
GRUB_TIMEOUT=0
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
END
    echo 'RUN_FIRSTBOOT=NO' > ${ROOTFS}/etc/sysconfig/firstboot

    if test -n "${ROOTFS}"; then
        chroot ${ROOTFS} grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
else
    echo >&2 "Skipping $0, as it is not EL7 ($RELEASE $ELVERSION)"
fi

