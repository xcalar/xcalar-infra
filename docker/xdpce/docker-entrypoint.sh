#!/bin/sh

xcalarctlpath=/opt/xcalar/bin/xcalarctl
if [ -f "$xcalarctlpath" ]; then
    $xcalarctlpath start
else
    echo "there is probably not xcalar installed yet...."
fi
bash
