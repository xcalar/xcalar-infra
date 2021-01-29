#!/bin/bash
# Run in the host, with the cwd being the root of the guest

set -x
cp tmp/network_interfaces.VM_NAME_GOES_HERE etc/network/interfaces
cp tmp/hosts.VM_NAME_GOES_HERE etc/hosts

# re-generate the keys. Letting virt-sysprep remove the keys
# is insufficient, and they don't get automatically regenerated
# on boot by Ubuntu. A dpkg-reconfigure fails for some reason,
# and doing a boot-time script is overkill, so just do it now explicitly.
rm etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub
rm etc/ssh/ssh_host_dsa_key etc/ssh/ssh_host_dsa_key.pub
rm etc/ssh/ssh_host_ecdsa_key etc/ssh/ssh_host_ecdsa_key.pub
ssh-keygen -h -N '' -t rsa -f etc/ssh/ssh_host_rsa_key
ssh-keygen -h -N '' -t dsa -f etc/ssh/ssh_host_dsa_key
ssh-keygen -h -N '' -t ecdsa -f etc/ssh/ssh_host_ecdsa_key
