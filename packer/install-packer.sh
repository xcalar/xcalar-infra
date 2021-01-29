#!/bin/bash
set -ex
cd /tmp
curl -sSL https://releases.hashicorp.com/packer/0.10.1/packer_0.10.1_linux_amd64.zip > packer.zip
if ! command -v unzip &>/dev/null; then
    sudo apt-get install -yqq unzip
fi
unzip packer.zip
rm -f packer.zip
chmod +x packer
sudo mv packer /usr/local/bin/
