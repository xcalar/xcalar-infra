#!/bin/bash


if [ $# -ne 1 ]; then
  echo >&2 "Usage: $0 <sizeofswap in GB>"
  exit 1
fi

GB="$1"

SWAP=${SWAP:-/swapfile}

if test -e $SWAP; then
  swapoff $SWAP || true
  sed -i.bak  '\@^'$SWAP'@d' /etc/fstab
  rm -f $SWAP
fi

echo >&2 "Creating ${GB}G size swap in $SWAP ..."
dd if=/dev/zero of=$SWAP bs=1024 count=$(( GB*1024*1024 ))
chmod 0600 $SWAP
mkswap -f $SWAP
echo "$SWAP  swap  swap   defaults 0 0" | tee -a /etc/fstab >/dev/null
swapon $SWAP
