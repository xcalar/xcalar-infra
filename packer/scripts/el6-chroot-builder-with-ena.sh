#!/bin/bash -ex

DEVICE=${1:-/dev/xvdf}
ROOTFS=${2:-/mnt/rootfs}
IXGBEVF_VER=${IXGBEVF_VER:-3.2.2}
ENA_VER=${ENA_VER:-1.1.3}
ENA_COMMIT=${ENA_COMMIT:-ba89b1e}
ENA_REPO=https://github.com/ambakshi/amzn-drivers.git
TMPDIR=/tmp/$(id -un)/$$

if ! test -b "${DEVICE}1"; then
    partprobe
    parted ${DEVICE} -s -- "mklabel msdos mkpart primary ext4 1M 100% set 1 boot on print"
    partprobe

    until test -b ${DEVICE}1; do
        echo "Waiting for ${DEVICE}1 ..."
        sleep 2
    done
    mkfs.ext4 -F -L root ${DEVICE}1
fi
if ! mountpoint -q "$ROOTFS"; then
    mkdir -p $ROOTFS
    mount ${DEVICE}1 $ROOTFS
    DIDMOUNT="${ROOTFS}"
fi

eval `blkid ${DEVICE}1 | tr ' ' '\n' | grep '^UUID='`
if test -z "$UUID"; then
    exit 1
fi

rpm --root=$ROOTFS --initdb
rpm --root=$ROOTFS -ivh http://mirror.centos.org/centos/6/os/x86_64/Packages/centos-release-6-9.el6.12.3.x86_64.rpm
sed -r -i -e 's/^mirrorlist/#mirrorlist/g; s/^#baseurl/baseurl/g' ${ROOTFS}/etc/yum.repos.d/CentOS-Base.repo
yum --installroot=$ROOTFS --nogpgcheck -y ${Q} --exclude='iwl*,ql*,aic*,*-firmware' groupinstall core
yum --installroot=$ROOTFS --nogpgcheck -y ${Q} install openssh-server acpid tuned kernel epel-release

cp -a /etc/skel/.bash* ${ROOTFS}/root

## Networking setup
cat > ${ROOTFS}/etc/hosts << END
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
END
touch ${ROOTFS}/etc/resolv.conf
cat > ${ROOTFS}/etc/sysconfig/network << END
NETWORKING=yes
NOZEROCONF=yes
HOSTNAME=localhost.localdomain
END
cat > ${ROOTFS}/etc/sysconfig/network-scripts/ifcfg-eth0  << END
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
END

cp /usr/share/zoneinfo/UTC ${ROOTFS}/etc/localtime

echo 'ZONE="UTC"' > ${ROOTFS}/etc/sysconfig/clock

# fstab
cat > ${ROOTFS}/etc/fstab << END
UUID=$UUID  /           ext4    defaults,relatime  1 1
tmpfs       /dev/shm    tmpfs   defaults           0 0
devpts      /dev/pts    devpts  gid=5,mode=620     0 0
sysfs       /sys        sysfs   defaults           0 0
proc        /proc       proc    defaults           0 0
END


#BINDMNTS="dev sys etc/hosts etc/resolv.conf"
#for d in $BINDMNTS ; do
#    mountpoint -q ${ROOTFS}/${d} || {
#    mount --bind /${d} ${ROOTFS}/${d}
#    DIDMOUNT="$DIDMOUNT ${d}"
#  }
#done
#mountpoint -q ${ROOTFS}/proc || {
#    mount -t proc none ${ROOTFS}/proc
#    DIDMOUNT="$DIDMOUNT ${d}"
#}

# Install cloud-init from epel
yum --installroot=$ROOTFS --nogpgcheck -y ${Q} install cloud-init cloud-utils-growpart gdisk dracut-modules-growroot
chroot ${ROOTFS} chkconfig sshd on
chroot ${ROOTFS} chkconfig cloud-init on

curl http://repo.xcalar.net/scripts/install-aws-deps.sh > ${ROOTFS}/tmp/install-aws-deps.sh
chroot ${ROOTFS} bash -ex /tmp/install-aws-deps.sh
# Configure cloud-init
cat > ${ROOTFS}/etc/cloud/cloud.cfg << END
users:
 - default

disable_root: 1
ssh_pwauth:   0

locale_configfile: /etc/sysconfig/i18n
mount_default_fields: [~, ~, 'auto', 'defaults,nofail', '0', '2']
resize_rootfs_tmp: /dev
ssh_deletekeys:   True
ssh_genkeytypes:  ~
syslog_fix_perms: ~

cloud_init_modules:
 - migrator
 - bootcmd
 - write-files
 - growpart
 - resizefs
 - set_hostname
 - update_hostname
 - update_etc_hosts
 - rsyslog
 - users-groups
 - ssh

cloud_config_modules:
 - mounts
 - locale
 - set-passwords
 - yum-add-repo
 - package-update-upgrade-install
 - timezone
 - puppet
 - chef
 - salt-minion
 - mcollective
 - disable-ec2-metadata
 - runcmd

cloud_final_modules:
 - rightscale_userdata
 - scripts-per-once
 - scripts-per-boot
 - scripts-per-instance
 - scripts-user
 - ssh-authkey-fingerprints
 - keys-to-console
 - phone-home
 - final-message

system_info:
  default_user:
    name: ec2-user
    lock_passwd: true
    gecos: Cloud User
    groups: [wheel, adm]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  distro: rhel
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
  ssh_svcname: sshd

datasource_list: [ Ec2, None ]

# vim:syntax=yaml
END

# Add additional AWS drivers
KVER=$(chroot $ROOTFS rpm -q kernel | tail -1 | sed -e 's/^kernel-//')
if false; then
cat > ${ROOTFS}/boot/grub/grub.conf << END
default=0
timeout=1
hiddenmenu
serial --unit=0 --speed=115200
terminal --timeout=1 serial console
title CentOS ($KVER)
        root (hd0,0)
        kernel /boot/vmlinuz-$KVER ro root=UUID=$UUID LANG=en_US.UTF-8 console=ttyS0,115200 crashkernel=auto KEYBOARDTYPE=pc
        initrd /boot/initramfs-${KVER}.img


END
ln -sfn grub.conf ${ROOTFS}/boot/grub/menu.lst
echo 'RUN_FIRSTBOOT=NO' > ${ROOTFS}/etc/sysconfig/firstboot
cat > ${ROOTFS}/boot/grub/device.map << EOF
(hd0,0)   /dev/disk/by-uuid/$UUID
EOF
grub-install --root-directory=${ROOTFS} hd1
else

##grub config taken from /etc/sysconfig/grub on RHEL7 AMI
cat > ${ROOTFS}/boot/grub/grub.conf << END
default=0
timeout=1
hiddenmenu


END
# configure grub and get the initrd straight
ln -sfn grub.conf ${ROOTFS}/boot/grub/menu.lst
for KERNELVER in `rpm --root $ROOTFS --query --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel`; do
    INITRAMFS="/boot/initramfs-${KERNELVER}.img"
    VMLINUZ="/boot/vmlinuz-${KERNELVER}"
    echo "Running: dracut --force --add-drivers \"ixgbevf eno virtio\" ${INITRAMFS} ${KERNELVER}";
    chroot $ROOTFS dracut --force --add-drivers "ixgbevf eno virtio" ${INITRAMFS} ${KERNELVER}
    echo "Adding to ${VMLINUZ} to grub.conf"
    (
    echo "title CentOS6 ${KERNELVER}";
    echo "  root (hd0,0)";
    echo "  kernel ${VMLINUZ} ro root=UUID=$UUID console=ttyS0 xen_blkfront.sda_is_xvda=1 verbose";
    echo "  initrd ${INITRAMFS}";
    echo "" ) >> $ROOTFS/boot/grub/grub.conf;
done

# configure grub
grub-install --root-directory=${ROOTFS} hd1 || true
setarch x86_64 \
    chroot $ROOTFS \
    env -i \
    echo -e "device (hd0) ${DEVICE}\nroot (hd0,0)\nsetup (hd0)" \
        | grub --device-map=/dev/null --batch
cat > $ROOTFS/boot/grub/device.map << EOL
(hd0) /dev/sda1
EOL

fi
#echo 'RUN_FIRSTBOOT=NO' > ${ROOTFS}/etc/sysconfig/firstboot
#cat > ${ROOTFS}/boot/grub/device.map << EOF
#(hd0,0)   /dev/disk/by-uuid/$UUID
#EOF

# Enable sr-iov
yum --installroot=$ROOTFS --nogpgcheck -y ${Q} install dkms make kernel-devel-$KVER perl
curl -L http://sourceforge.net/projects/e1000/files/ixgbevf%20stable/${IXGBEVF_VER}/ixgbevf-${IXGBEVF_VER}.tar.gz/download > /tmp/ixgbevf.tar.gz
tar zxf /tmp/ixgbevf.tar.gz -C ${ROOTFS}/usr/src
# Newer drivers are missing InterruptThrottleRate - patch the old one instead
#yum -y -q install patch
#curl -L https://sourceforge.net/p/e1000/bugs/_discuss/thread/a5c4e75f/837d/attachment/ixgbevf-3.2.2_rhel73.patch |
#  patch -p1 -d ${ROOTFS}/usr/src/ixgbevf-${IXGBEVF_VER}
cat > ${ROOTFS}/usr/src/ixgbevf-${IXGBEVF_VER}/dkms.conf << END
PACKAGE_NAME="ixgbevf"
PACKAGE_VERSION="${IXGBEVF_VER}"
CLEAN="cd src/; make clean"
MAKE="cd src/; make BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_LOCATION[0]="src/"
BUILT_MODULE_NAME[0]="ixgbevf"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="ixgbevf"
AUTOINSTALL="yes"
END
chroot $ROOTFS dkms add -m ixgbevf -v ${IXGBEVF_VER}
chroot $ROOTFS dkms build -m ixgbevf -v ${IXGBEVF_VER} -k $KVER
chroot $ROOTFS dkms install -m ixgbevf -v ${IXGBEVF_VER} -k $KVER
echo "options ixgbevf InterruptThrottleRate=1,1,1,1,1,1,1,1" > ${ROOTFS}/etc/modprobe.d/ixgbevf.conf
# Enable Amazon ENA
# Create an archive file locally from git first

rm -rf ${TMPDIR}/ena
mkdir -p ${TMPDIR}/ena
git clone ${ENA_REPO} ${TMPDIR}/ena
cd ${TMPDIR}/ena
git archive --prefix ena-${ENA_VER}/ ${ENA_COMMIT} | tar xC ${ROOTFS}/usr/src
if [[ "${ENA_COMMIT}" = "3ac3e0b" ]]; then
    (cd ${ROOTFS}/usr/src/ena-${ENA_VER} && curl -sSL http://repo.xcalar.net/deps/ena-1.1.3_rhel6.patch | patch -p1)
fi
cat > ${ROOTFS}/usr/src/ena-${ENA_VER}/dkms.conf << END
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
chroot $ROOTFS dkms add -m ena -v ${ENA_VER}
chroot $ROOTFS dkms dkms build -m ena -v ${ENA_VER} -k ${KVER}
chroot $ROOTFS dkms install -m ena -v ${ENA_VER} -k ${KVER}

#Disable SELinux
sed -i -e 's/^\(SELINUX=\).*/\1disabled/' ${ROOTFS}/etc/selinux/config

# Remove EPEL
#yum --installroot=$ROOTFS -C -y remove epel-release --setopt="clean_requirements_on_remove=1"

# We're done!
#for d in $DIDMOUNT; do
#  umount ${ROOTFS}/${d}
#done
sync
