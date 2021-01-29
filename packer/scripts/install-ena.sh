#!/bin/bash
#
# Build Amazon's ENA Enhanced Networking driver from source. Should be run
# on an instance with enhanced networking (r4,i3,c5,m5,etc)

DEVICE=$1
ROOTFS=$2
IXGBEVF_VER=${IXGBEVF_VER:-3.2.2}
ENA_VER=${ENA_VER:-1.5.0}
ENA_COMMIT=${ENA_COMMIT:-7dd2f96}

#ENA_REPO=https://github.com/ambakshi/amzn-drivers.git
# Amazon's official repo is safe to use since they merged my change
ENA_REPO=https://github.com/amzn/amzn-drivers
USE_RPM=true
TMPDIR=/tmp/$(id -un)/$$
RELEASE="${RELEASE:-$(rpm -q $(rpm -qf /etc/redhat-release) --qf '%{VERSION}')}"
SELINUX="${SELINUX:-permissive}"
KVER="${KVER:-$(rpm -q kernel | tail -1 | sed -e 's/^kernel-//')}"

mkdir -p ${TMPDIR}

dchroot () {
    local root="$1"
    shift
    echo >&2 "chroot ${root}: $@"
    if [ "$root" != "" ] && [ "$root" != / ]; then
        chroot $root "$@"
    else
        "$@"
    fi
}

install_ena () {
    if [ "${USE_RPM}" == false ]; then
        rm -rf ${TMPDIR}/ena
        mkdir -p ${TMPDIR}/ena
        git clone ${ENA_REPO} ${TMPDIR}/ena
        cd ${TMPDIR}/ena
        git archive --prefix ena-${ENA_VER}/ ${ENA_COMMIT} | tar xC ${ROOTFS}/usr/src
        cat > ${ROOTFS}/usr/src/ena-${ENA_VER}/dkms.conf <<END
PACKAGE_NAME="ena"
PACKAGE_VERSION="${ENA_VER}"
CLEAN="make -C kernel/linux/ena clean"
MAKE="make -C kernel/linux/ena/ BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_NAME[0]="ena"
BUILT_MODULE_LOCATION="kernel/linux/ena"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="ena"
AUTOINSTALL="yes"
END
        dchroot "${ROOTFS}" dkms add -m ena -v ${ENA_VER}
        dchroot "${ROOTFS}" dkms dkms build -m ena -v ${ENA_VER} -k ${KVER}
        dchroot "${ROOTFS}" dkms install -m ena -v ${ENA_VER} -k ${KVER}
        dchroot "${ROOTFS}" mkinitrd -f -v /boot/initrd-${KVER}.img ${KVER}
    else
        rm -rf ${ROOTFS}/usr/src/ena-${ENA_VER}
        git clone ${ENA_REPO} ${ROOTFS}/usr/src/ena-${ENA_VER}
        (cd ${ROOTFS}/usr/src/ena-${ENA_VER} && git checkout -f ${ENA_COMMIT})
        dchroot "${ROOTFS}" bash -c "cd /usr/src/ena-${ENA_VER}/kernel/linux/rpm && make rpm TAG=master"
        cp ${ROOTFS}/usr/src/ena-${ENA_VER}/kernel/linux/rpm/x86_64/kmod-ena-${ENA_VER}*.rpm .
        cp ${ROOTFS}/usr/src/ena-${ENA_VER}/kernel/linux/rpm/ena-${ENA_VER}*.rpm .
    fi
}

install_deps () {
    yum update -y
    yum groupinstall -y 'Development tools'
    yum install -y dkms make dracut-config-generic dracut-network dracut git kernel-devel
}

install_deps
install_ena
if test -e "${ROOTFS}/boot/initramfs-${KVER}.img"; then
    dchroot "${ROOTFS}" rpm -Uvh /usr/src/ena-${ENA_VER}/kernel/linux/rpm/x86_64/kmod-ena-${ENA_VER}*.rpm
    dchroot "${ROOTFS}" dracut --add-drivers "nvme ena virtio"  -v --kver ${KVER} -f /boot/initramfs-${KVER}.img ${KVER}
else
    echo "Please run:"
    echo "dracut --add-drivers "nvme ena virtio"  -v --kver ${KVER} -f /boot/initramfs-${KVER}.img ${KVER}"
fi
