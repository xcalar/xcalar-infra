#!/bin/bash


set -ex

export http_proxy="${http_proxy-http://localhost:3128}"

DEVICE=${1:-/dev/xvdf}
ROOTFS=${2:-/mnt/rootfs}
IXGBEVF_VER=0
IPV6=${IPV6:-true}
ENA_VER=${ENA_VER:-2.0.2}
ENA_COMMIT=${ENA_COMMIT:-46621be3}
ENA_REPO=https://github.com/ambakshi/amzn-drivers.git
USE_RPM=false
TMPDIR=/tmp/$(id -un)/$$

RELEASE="${RELEASE:-7.6}"
SELINUX="${SELINUX:-disabled}"
CR=http://mirror.centos.org/centos/7/os/x86_64/Packages
REPO=https://storage.googleapis.com/repo.xcalar.net
KVER="${KVER:-$(rpm -q kernel | tail -1 | sed -e 's/^kernel-//')}"
if [[ $DEVICE =~ nvme ]]; then
  P=p
fi
if $IPV6; then
    IPV6_YN=yes
else
    IPV6_YN=no
fi

if ! test -b "${DEVICE}${P}1"; then
    partprobe
    parted ${DEVICE} -s -- "mktable gpt mkpart primary ext2 1 2 set 1 bios_grub on mkpart primary xfs 2 100%"
    partprobe

    until test -b ${DEVICE}${P}2; do
        echo "Waiting for ${DEVICE}${P}2 ..."
        sleep 2
    done
    mkfs.xfs -f -L root -n ftype=1 ${DEVICE}${P}2
fi
if ! mountpoint -q "${ROOTFS}"; then
    mkdir -p ${ROOTFS}
    mount ${DEVICE}${P}2 ${ROOTFS}
    DIDMOUNT="${ROOTFS}"
fi

# Get UUID, LABEL, etc
eval `blkid ${DEVICE}${P}2 | cut -d' ' -f 2-`

yum clean all
rm -rf /var/cache/yum/*
yum makecache fast
rpm --rebuilddb
rpm --root=${ROOTFS} --initdb
if [ "${RELEASE}" = 7.2 ]; then
    rpm --root=${ROOTFS} -ivh http://repo.xcalar.net/deps/centos-release-7-2.1511.el7.centos.2.10.x86_64.rpm
elif [ "${RELEASE}" = 7.3 ]; then
    rpm --root=${ROOTFS} -ivh http://mirror.centos.org/centos/7/os/x86_64/Packages/centos-release-7-3.1611.el7.centos.x86_64.rpm
elif [ "${RELEASE}" = 7.4 ]; then
    #rpm --root=${ROOTFS} -Uvh http://repo.xcalar.net/mirror/xcalar-rhel7-mirror-1.0-2.el7.x86_64.rpm
    rpm --root=${ROOTFS} -Uvh http://mirror.centos.org/centos/7/os/x86_64/Packages/centos-release-7-4.1708.el7.centos.x86_64.rpm
elif [ "${RELEASE}" = 7.5 ]; then
    PKGS=($REPO/deps/centos-release-7-5.1804.5.el7.centos.x86_64.rpm) # $CR/bash-4.2.46-30.el7.x86_64.rpm $CR/grep-2.20-3.el7.x86_64.rpm $CR/coreutils-8.22-21.el7.x86_64.rpm)
    rpm --root=${ROOTFS} --nodeps -ivh "${PKGS[0]}"
    #rpm --root=${ROOTFS} --nodeps -Uvh "${PKGS[@]}"
    #yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} localinstall "${PKGS[@]}"
elif [ "$RELEASE" = 7.6 ]; then
    PKGS=(http://mirror.centos.org/centos/7/os/x86_64/Packages/centos-release-7-6.1810.2.el7.centos.x86_64.rpm)
    rpm --root=${ROOTFS} --nodeps -ivh "${PKGS[0]}"
fi
if [ $? -ne 0 ]; then
    echo >&2 "ERROR: Unable to install base package"
    exit 1
fi
#yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} --exclude='iwl*,ql*,aic*' groupinstall core
#sed -r -i -e 's/^mirrorlist/#mirrorlist/g; s/^#baseurl/baseurl/g' ${ROOTFS}/etc/yum.repos.d/CentOS-Base.repo
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} groups mark-install core
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} --exclude='ql*,ivtv*,aic94xx-firmware*,alsa-*,iwl*,NetworkManager*,avahi*,iprutils,kexec-tools' group install core
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} install openssh-server grub2 acpid tuned epel-release mdadm lvm2 kernel{,-devel,-headers,-tools}-${KVER} coreutils grep yum-utils nfs-utils dnsmasq
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} install cloud-init cloud-utils-growpart gdisk dkms make dracut-config-generic dracut-network dracut unzip nvme-cli openssl rsyslog chrony ansible
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} install iftop iperf3 htop sysstat perf procps-ng util-linux bash-completion psmisc strace tmux logrotate cronie at libcgroup-tools libcgroup
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} install ${REPO}/xcalar-release-el7.rpm
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} --enablerepo='xcalar-deps*' install ephemeral-disk ec2tools amazon-efs-utils consul consul-template nomad vault fatrace bcache-tools direnv caddy fabio su-exec

#yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} install http://repo.xcalar.net/deps/{kernel,kernel-devel,kernel-headers}-${KVER}.rpm
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} remove NetworkManager --setopt="clean_requirements_on_remove=1"
yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} remove xcalar-release

ls ${ROOTFS}/etc/yum.repos.d/CentOS-*.repo | grep -v CentOS-Base | xargs rm -vf
sed -i '/^\[updates\]/,/^$/d' ${ROOTFS}/etc/yum.repos.d/CentOS-Base.repo

cp -a /etc/skel/.bash* ${ROOTFS}/root

cat > ${ROOTFS}/etc/hosts << END
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
END
cp /etc/resolv.conf ${ROOTFS}/etc/resolv.conf
cat > ${ROOTFS}/etc/sysconfig/network << END
NETWORKING=yes
NOZEROCONF=yes
NETWORKING_IPV6=${IPV6_YN}
END

# Jesus, this took forever to figure out.
# Reference: https://www.emilsit.net/blog/archives/how-to-configure-linux-networking-for-ec2-amis/
cat > ${ROOTFS}/etc/sysconfig/network-scripts/ifcfg-eth0  << END
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=yes
PEERDNS=yes
IPV6INIT=${IPV6_YN}
PERSISTENT_DHCLIENT=yes
NM_CONTROLLED=no
# DHCPV6C=${IPV6_YN}
END

ln -sfn ../usr/share/zoneinfo/UTC ${ROOTFS}/etc/localtime

echo 'ZONE="UTC"' > ${ROOTFS}/etc/sysconfig/clock

# fstab
cat > ${ROOTFS}/etc/fstab << END
UUID="$UUID"    /         xfs    defaults,relatime  0   0
END

#grub config taken from /etc/sysconfig/grub on RHEL7 AMI
cat > ${ROOTFS}/etc/default/grub <<'END'
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
END
echo 'RUN_FIRSTBOOT=NO' > ${ROOTFS}/etc/sysconfig/firstboot
ln -s /dev/null ${ROOTFS}/etc/udev/rules.d/80-net-name-slot.rules
#rm -f ${ROOTFS}/etc/udev/rules.d/70-persistent-net.rules

# BINDMNTS="dev sys etc/hosts etc/resolv.conf"
#
# for d in $BINDMNTS ; do
#   mountpoint -q ${ROOTFS}/${d} || {
# 		mount --bind /${d} ${ROOTFS}/${d}
# 		DIDMOUNT="$DIDMOUNT ${d}"
#   }
# done
# mountpoint -q ${ROOTFS}/proc || {
# 	mount -t proc none ${ROOTFS}/proc
# 	DIDMOUNT="$DIDMOUNT ${d}"
# }
# # Install grub2
chroot ${ROOTFS} grub2-mkconfig -o /boot/grub2/grub.cfg
chroot ${ROOTFS} grub2-install $DEVICE
# Install cloud-init from epel
#chroot ${ROOTFS} yum clean all
#chroot ${ROOTFS} yum makecache fast
#chroot ${ROOTFS} yum --nogpgcheck -y ${Q} --exclude='kernel*' install cloud-init cloud-utils-growpart gdisk
chroot ${ROOTFS} systemctl enable sshd.service
chroot ${ROOTFS} systemctl enable cloud-init.service
chroot ${ROOTFS} systemctl enable chronyd.service
chroot ${ROOTFS} systemctl enable crond.service
chroot ${ROOTFS} systemctl enable atd.service
chroot ${ROOTFS} systemctl enable rsyslog.service
chroot ${ROOTFS} systemctl disable firewalld.service
chroot ${ROOTFS} systemctl mask tmp.mount

#curl -L https://s3.amazonaws.com/aws-cli/awscli-bundle.zip -o ${ROOTFS}/tmp/awscli-bundle.zip
#
#cd ${ROOTFS}/tmp && unzip awscli-bundle.zip && cd -
#chroot ${ROOTFS} /tmp/awscli-bundle/install -i ${ROOTFS}/opt/aws -b ${ROOTFS}/usr/local/bin/aws
#curl ${REPO}/scripts/install-aws-deps.sh > ${ROOTFS}/tmp/install-aws-deps.sh
cp /netstore/scripts/install-aws-deps.sh ${ROOTFS}/tmp/install-aws-deps.sh

chroot ${ROOTFS} bash -ex /tmp/install-aws-deps.sh

# Configure cloud-init
cat > ${ROOTFS}/etc/cloud/cloud.cfg << END
users:
 - default

disable_root: 1
ssh_pwauth:   0

mount_default_fields: [~, ~, 'auto', 'defaults,nofail', '0', '2']
resize_rootfs_tmp: /dev
ssh_svcname: sshd
ssh_deletekeys:   True
ssh_genkeytypes:  [ 'rsa', 'ecdsa', 'ed25519' ]
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
    groups: [wheel, adm, systemd-journal]
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
VMAJ=7
VMIN=6

if [ $VMAJ -eq 7 ] && [ $VMIN -ge 4 ]; then
    mkdir -p ${ROOTFS}/etc/cloud/cloud.cfg.d
    cat > ${ROOTFS}/etc/cloud/cloud.cfg.d/90-networking-disabled.cfg <<EOF
network:
  config: disabled
EOF
#    cat > ${ROOTFS}/etc/cloud/cloud.cfg.d/99-custom-networking.cfg <<EOF
#network:
#  version: 1
#  config:
#  - type: physical
#    name: eth0
#    subnets:
#      - type: dhcp6
#EOF
fi

DRIVERS="nvme virtio"
# Add additional AWS drivers
# Enable sr-iov
#yum --installroot=${ROOTFS} --nogpgcheck -y ${Q} --exclude='kernel*' install dkms make
if [ -n "$IXGBEVF_VER" ] && [ "$IXGBEVF_VER" != 0 ]; then # && [ "$RELEASE" != "7.4" ]; then
    curl -fL http://sourceforge.net/projects/e1000/files/ixgbevf%20stable/${IXGBEVF_VER}/ixgbevf-${IXGBEVF_VER}.tar.gz/download -o /tmp/ixgbevf.tar.gz
    tar zxf /tmp/ixgbevf.tar.gz -C ${ROOTFS}/usr/src
    # Newer drivers are missing InterruptThrottleRate
    if [[ "$IXGBEVF_VER" = "3.2.2" ]]; then
        curl -L https://sourceforge.net/p/e1000/bugs/_discuss/thread/a5c4e75f/837d/attachment/ixgbevf-3.2.2_rhel73.patch |
            patch -p1 -d ${ROOTFS}/usr/src/ixgbevf-${IXGBEVF_VER}
    fi
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
    chroot ${ROOTFS} dkms add -m ixgbevf -v ${IXGBEVF_VER}
    chroot ${ROOTFS} dkms build -m ixgbevf -v ${IXGBEVF_VER} -k ${KVER}
    chroot ${ROOTFS} dkms install -m ixgbevf -v ${IXGBEVF_VER} -k ${KVER}
    if [[ "$IXGBEVF_VER" = "3.2.2" ]]; then
        echo "options ixgbevf InterruptThrottleRate=1,1,1,1,1,1,1,1" > ${ROOTFS}/etc/modprobe.d/ixgbevf.conf
    fi
    DRIVERS="$DRIVERS ixgbevf"
fi

# Enable Amazon ENA
if [ "${USE_RPM}" == false ]; then
    rm -rf ${TMPDIR}/ena
    mkdir -p ${TMPDIR}/ena
    git clone ${ENA_REPO} ${TMPDIR}/ena
    cd ${TMPDIR}/ena
    git archive --prefix ena-${ENA_VER}/ ${ENA_COMMIT} | tar xC ${ROOTFS}/usr/src
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
    chroot ${ROOTFS} dkms add -m ena -v ${ENA_VER}
    chroot ${ROOTFS} dkms build -m ena -v ${ENA_VER} -k ${KVER}
    chroot ${ROOTFS} dkms install -m ena -v ${ENA_VER} -k ${KVER}
else
    git clone ${ENA_REPO} ${ROOTFS}/usr/src/ena-${ENA_VER}
    (cd ${ROOTFS}/usr/src/ena-${ENA_VER} && git checkout -f ${ENA_COMMIT})
    chroot ${ROOTFS} make -C /usr/src/ena-${ENA_VER}/kernel/linux/rpm rpm
    chroot ${ROOTFS} rpm -Uvh /usr/src/ena-${ENA_VER}/kernel/linux/x86_64/kmod-ena-${ENA_VER}*.rpm
fi

DRIVERS="ena $DRIVERS"

#chroot ${ROOTFS} dracut --add-drivers "$DRIVERS"  -v --kver ${KVER} -f /boot/initramfs-${KVER}.img ${KVER}
cat > ${ROOTFS}/etc/dracut.conf.d/ena.conf <<EOF
add_drivers+="$DRIVERS"
EOF
#chroot ${ROOTFS} mkinitrd -f -v /boot/initrd-${KVER}.img ${KVER}
chroot ${ROOTFS} dracut --add-drivers="$DRIVERS" -f --kver ${KVER} -v
chroot ${ROOTFS} lsinitrd /boot/initramfs-${KVER}.img
chroot ${ROOTFS} dkms status
# chroot ${ROOTFS} systemctl disable dkms

chroot ${ROOTFS} yum clean all --enablerepo='*'
chroot ${ROOTFS} find /var/cache/yum/ -not -path /var/cache/yum/ -delete
chroot ${ROOTFS} find /tmp/ -not -path /tmp/ -delete
chroot ${ROOTFS} find /var/tmp/ -not -path /var/tmp/ -delete

#Disable SELinux
sed -i -e 's/^\(SELINUX=\).*/\1'${SELINUX}'/' ${ROOTFS}/etc/selinux/config

# Remove EPEL
# yum --installroot=${ROOTFS} -C -y remove epel-release --setopt="clean_requirements_on_remove=1"

#rm ${ROOTFS}/etc/resolv.conf
#mkdir -p ${ROOTFS}/usr/local/bin ${ROOTFS}/etc/bash_completion.d
#for ii in /opt/aws/bin/aws_completer; do
#    if test -x "$ii"; then
#        ln -vsfn "$ii" ${ROOTFS}/usr/local/bin/
#    fi
#done
#ln -sfn /opt/aws/bin/aws_bash_completer ${ROOTFS}/etc/bash_completion.sh

chroot ${ROOTFS} /usr/local/bin/aws --version

# We're done!
for d in $DIDMOUNT; do
  umount ${ROOTFS}/${d}
done
sync
