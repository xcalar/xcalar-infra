#!/bin/bash

set -e

yum install --enablerepo='epel' -y cloud-init cloud-utils-growpart gdisk

mkdir -p ${ROOTFS}/etc/cloud
cat >${ROOTFS}/etc/cloud/cloud.cfg <<END
users:
 - default

disable_root: 0
ssh_pwauth:   1

mount_default_fields: [~, ~, 'auto', 'defaults,nofail', '0', '2']
resize_rootfs_tmp: /dev
ssh_svcname: sshd
ssh_deletekeys:   False
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
    name: centos
    gecos: Cloud User
    groups: [wheel, adm, systemd-journal]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
  distro: rhel
  paths:
    cloud_dir: /var/lib/cloud
    templates_dir: /etc/cloud/templates
  ssh_svcname: sshd

datasource_list: [ NoCloud, None ]

# vim:syntax=yaml
END
mkdir -p ${ROOTFS}/etc/cloud/cloud.cfg.d
cat >${ROOTFS}/etc/cloud/cloud.cfg.d/90-networking-disabled.cfg <<EOF
network:
  config: disabled
EOF

systemctl enable cloud-init

exit 0

#    cat > ${ROOTFS}/etc/cloud/cloud.cfg.d/99-custom-networking.cfg <<EOF
#network:
#  version: 1
#  config:
#  - type: physical
#    name: eth0
#    subnets:
#      - type: dhcp6
#EOF
