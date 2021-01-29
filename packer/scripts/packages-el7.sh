#!/bin/bash
yum install -y http://repo.xcalar.net/xcalar-release-el7.rpm
yum erase -y 'ntp*'
yum install -y yum-utils epel-release curl wget tar gzip chrony
systemctl enable --now chronyd

if [[ $PACKER_BUILDER_TYPE =~ amazon ]]; then
    yum install --enablerepo='xcalar-*' -y amazon-efs-utils ec2tools ec2-utils
fi
