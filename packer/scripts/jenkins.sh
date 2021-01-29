#!/bin/sh

# Store build time
date > /etc/packer_box_build_time

export USR=jenkins
export HME=/home/jenkins
if ! id $USR >/dev/null; then
    useradd -m -d  $HME -s /bin/bash $USR
fi

# Set up sudo
echo "$USR ALL=NOPASSWD:ALL" > /etc/sudoers.d/$USR
chmod 0440 /etc/sudoers.d/$USR

# Install vagrant key
mkdir -pm 700 $HME/.ssh /var/lib/jenkins
curl -sSL http://repo.xcalar.net/xcalar.pub > $HME/.ssh/authorized_keys
curl -sSL https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub >> $HME/.ssh/authorized_keys
chmod 0600 $HME/.ssh/authorized_keys
chown -R $USR:$USR $HME /var/lib/jenkins

if ! getent group sudo; then
    groupadd sudo
fi
if ! getent group disk; then
    groupadd disk
fi


usermod -aG sudo,docker,disk $USR

# NFS used for file syncing
if test -e /etc/redhat-release; then
    yum install -y nfs-utils
else
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq nfs-common
fi
