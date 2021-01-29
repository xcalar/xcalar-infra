#!/bin/bash
#
# Extend a lvm logical volume with a new disk
#
# usage:
#   $ lvm-extend.sh <lvname> <devicename>
#
# eg:
#	$ lvm-extend.sh turing-share/share  sde
#

if [ `id -u` -ne 0 ]; then
	echo >&2 "Must run as root"
	exit 1
fi

LV="$1"
DEV="$2"

if [ -z "$LV" ] || [ -z "$DEV" ]; then
	echo >&2 "Must specify the logical volume to extend, in the format of VolGroup/LogicalVol"
	echo >&2 "and the device to extend it with. eg:"
	echo >&2 "$0 turing-share/share sde"
	exit 1
fi

VGROUP="$(dirname $LV)"
LVOL="$(basename $LV)"
if ! test -b /dev/$LV || ! lvdisplay $LV; then
	echo >&2 "Unable to find logical volume $LV"
	exit 1
fi

if ! test -b /dev/$DEV; then
	echo >&2 "$DEV is not a valid block device"
	exit 1
fi

read -p "Are you sure you want to extend /dev/$LV with /dev/$DEV? [y/N] " YesNo

if [ "$YesNo" = "Y" ]; then
	set -ex
	pvcreate /dev/$DEV
	vgextend $VGROUP /dev/$DEV
	lvextend -l +100%FREE /dev/$LV
	resize2fs /dev/$LV
else
    echo >&2 "No action taken (type 'Y' for yes)"
fi

