#!/bin/bash
set -x

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-kernel-server nfs-common iperf3 vim-nox htop iftop sysstat iozone3

for BLKDEV in /dev/disk/by-id/nvme-nvme_card_nvme_card /dev/nvme0n1 /dev/sdb; do
    if test -b $BLKDEV; then
        break
    fi
done
if ! test -b $BLKDEV; then
    exit 1
fi
case "$BLKDEV" in
    /dev/disk/by-id/*) PART="${BLKDEV}-part1";;
    /dev/nvme*) PART="${BLKDEV}p1";;
    /dev/sd*) PART="${BLKDEV}1";;
    /dev/xvd*) PART="${BLKDEV}1";;
    *) echo >&2 "Unknown partition type"; exit 1;;
esac

if ! test -b "$PART"; then
    parted "$BLKDEV" -s 'mklabel gpt mkpart primary 1 -1'
    sleep 5
    until mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$PART"; do
        sleep 5
    done
fi

# In 512-byte blocks
blockdev --setra 1024 "$PART"
sed -i '/\/srv\/share/d' /etc/fstab /etc/exports
mkdir -p /srv/share
echo "UUID=$(blkid -s UUID -o value $PART) /srv/share  ext4    relatime,discard,defaults,nofail,nobarrier  0   2" | tee -a /etc/fstab
mount /srv/share
mkdir -p -m 0777 /srv/share/nfs/cluster
chmod 0777 /srv/share/nfs/cluster

echo "/srv/share/nfs       *(rw,all_squash,async,no_subtree_check)" >> /etc/exports

sed -i 's/^RPCNFSDCOUNT=.*$/RPCNFSDCOUNT=16/g' /etc/default/nfs-kernel-server
service nfs-kernel-server restart
