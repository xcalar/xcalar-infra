#!/bin/sh

# Store build time
date > /etc/vagrant_box_build_time

ADDUSER=xcalardev

if ! id $ADDUSER >/dev/null; then
    groupadd --non-unique -g 1000 $ADDUSER
    useradd -m -s /bin/bash --non-unique -u 1000 -g $ADDUSER -G docker,disk,sudo $ADDUSER
fi

# Set up sudo
echo '$ADDUSER ALL=NOPASSWD:ALL' > /etc/sudoers.d/$ADDUSER

# Install $ADDUSER's keys
mkdir -pm 700 /home/$ADDUSER/.ssh
wget --no-check-certificate http://repo.xcalar.net/$ADDUSER.pub -O /home/$ADDUSER/.ssh/authorized_keys
chmod 0600 /home/$ADDUSER/.ssh/authorized_keys
chown -R $ADDUSER:$ADDUSER /home/$ADDUSER/.ssh

# NFS used for file syncing
apt-get install -yqq nfs-common
