#!/bin/bash

NAME="$1"
if [ -z "$NAME" ]; then
    echo "Must specify name"
    exit 1
fi

set -ex

BASE=/var/lib/libvirt/images/el7-minimal.qcow2
IMAGE=/var/lib/libvirt/images/${NAME}.qcow2


sudo rm -f $IMAGE
sudo qemu-img create -f qcow2 -b $BASE $IMAGE


UUID="$(echo  'import virtinst.util ; print virtinst.util.uuidToString(virtinst.util.randomUUID())' | python)"
MAC="$(echo 'import virtinst.util ; print virtinst.util.randomMAC()' | python)"


sed -e "s,@UUID@,$UUID,g" \
    -e "s,@NAME@,$NAME,g" \
    -e "s,@MAC@,$MAC,g" \
    -e "s,@IMAGE@,$IMAGE,g" \
    domain-tmpl.xml | tee ${NAME}.xml


virsh define ${NAME}.xml
virsh start ${NAME}

