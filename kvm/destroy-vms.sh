#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
TMPL="$1"
if [ -z "$TMPL" ]; then
    echo >&2 "Need to specify a template (el6-minimal, el7-minimal, ub14-minimal)"
    exit 1
fi
XML="$DIR/tmpl/${TMPL}.xml"
if ! test -e "$XML"; then
    echo >&2 "No template $XML found"
    exit 1
fi

BASE=/var/lib/libvirt/images/${TMPL}.qcow2

VMS="$(virsh list --all | tail -n+3 | awk '{print $2}' | grep "${TMPL}")"

if test -z "$VMS"; then
    echo "No VMs found for $TMPL"
    exit 0
fi

for vm in $VMS; do
    IMAGE=$(dirname $BASE)/${vm}.qcow2
    virsh destroy $vm
    virsh undefine $vm
done

