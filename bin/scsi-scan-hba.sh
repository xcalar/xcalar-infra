#!/bin/bash
#
# Use this script to scan the scsi host bus for new
# devices after adding disks in VCenter

if [ `id -u` -ne 0 ]; then
	echo >&2 "Must run as root"
	exit 1
fi

hostdev="$(grep mpt /sys/class/scsi_host/host*/proc_name | awk -F':' '{print $1}' | egrep -Eow 'host[0-9]+')"

if [ -z "$hostdev" ]; then
	echo >&2 "Unable to find mpt host device"
	exit 1
fi

echo "- - -" > /sys/class/scsi_host/$hostdev/scan

DEV="$(dmesg | tail -5 | sed -n -Ee 's/.*\[([a-z]+)\] Attached SCSI disk/\1/p')"

if test -n "$DEV" && test -b /dev/$DEV; then
	echo $DEV
	exit 0
fi

echo >&2 "Unable to find new device"
exit 1

