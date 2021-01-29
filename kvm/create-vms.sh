#!/bin/bash
#
# Spin up a KVM virtual machine
# See http://www.greenhills.co.uk/2013/03/24/cloning-vms-with-kvm.html

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPL="$1"
if [ -z "$TMPL" ]; then
    echo >&2 "Need to specify a template (el6-minimal, el7-minimal, ub14-minimal)"
    exit 1
fi
COUNT="$2"
if [ -z "$COUNT" ]; then
    COUNT=4
fi
XML="$DIR/tmpl/${TMPL}.xml"
if ! test -e "$XML"; then
    echo >&2 "No template $XML found"
    exit 1
fi


BASE=/var/lib/libvirt/images/${TMPL}.qcow2
sudo chmod 0755 /var/lib/libvirt/images
if ! test -e "$BASE"; then
    echo >&2 "Copying ${TMPL}.qcow2 from /netstore/isos/..."
    sudo cp /netstore/isos/${TMPL}.qcow2 /var/lib/libvirt/images
    if [ $? -ne 0 ]; then
        echo >&2 "Failed to copy image.."
        exit 1
    fi
    sudo chmod 0444 "$BASE"
fi

MAC_ADDRESS=(
0
`cat $DIR/tmpl/${TMPL}.mac`
)

for ii in `seq $COUNT`; do
    NAME=${TMPL}-${ii}
    IMAGE=$(dirname $BASE)/${NAME}.qcow2
    cat $DIR/tmpl/${TMPL}.xml | $DIR/modify-domain.py --name=$NAME --new-uuid --device-path=$IMAGE --mac-address=${MAC_ADDRESS[$ii]} > $DIR/vm/${NAME}.xml
    virsh destroy $NAME 2>/dev/null || :
    virsh dumpxml $NAME &>/dev/null && virsh undefine $NAME
    sudo qemu-img create -f qcow2 -b $BASE $IMAGE
    virsh define $DIR/vm/${NAME}.xml
    virsh start ${NAME}
done

