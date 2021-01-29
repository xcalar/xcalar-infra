#!/bin/bash

set -ex

REPO=https://storage.googleapis.com/repo.xcalar.net

add_osid() {
    curl -f -L ${REPO}/scripts/osid-201904 -o /usr/bin/osid
    chmod +x /usr/bin/osid
}

## setup sudo
setup_sudo() {
    if ! getent group sudo; then
        groupadd -r sudo
    fi

    mkdir -p /etc/sudoers.d
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-sudo
    chmod 0750 /etc/sudoers.d
    chmod 0440 /etc/sudoers.d/99-sudo

}

add_to_sudoers() {
    usermod -aG sudo $1
}

add_xcalar_repo() {
    rpm -q epel-release || yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    rpm -q xcalar-release || yum --nogpgcheck -y localinstall ${REPO}/xcalar-release-$(osid).rpm
}

yum_install() {
    yum install --enablerepo='epel' --enablerepo='xcalar*' -y "$@"
}


add_osid
setup_sudo
add_to_sudoers "azureuser"
add_xcalar_repo
yum_install xcalar-ssh-ca
