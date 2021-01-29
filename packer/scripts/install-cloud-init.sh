#!/bin/bash

yum install -y cloud-init

systemctl enable cloud-config
systemctl enable cloud-init
systemctl enable cloud-init-local
systemctl enable cloud-final

mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/90-networking.conf<<EOF
network:
  config: disabled
EOF
