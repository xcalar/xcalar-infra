#!/bin/bash

set -x

xcalarNodes=`echo "$Nodes" | python -c "import sys; print \" \".join([slave.split('==')[1].split(\"'\")[1] for slave in sys.stdin.readline().split('||')])"`

export XCE_CONFIG=/etc/xcalar/default.cfg
export XLRDIR=/opt/xcalar
export XLROPTDIR=/opt/xcalar
export PATH=$XLRDIR/bin:$PATH
export GenConfig="$XLRDIR/scripts/genConfig.sh"

set +e

sudo systemctl stop xcalar
ret=$?

if [ "$ret" != "0" ]; then
    echo "Failed to stop Xcalar. Forcefully murdering usrnodes now"
    sudo killall -s KILL usrnode
    sudo killall -s KILL childnode
    sudo killall -s KILL xcmgmtd
    pgrep -u `whoami` -f expServer | xargs -r kill -9
fi

shm=/dev/shm

sudo rm -rf /tmp/*build1
sudo rm -rf /tmp/cliTest.*
sudo rm -rf /tmp/LibDsTest.*
sudo rm -rf /tmp/launcher.*
sudo rm -rf /tmp/xcalar.output.*
sudo rm -rf /tmp/usrnode*
sudo rm -rf /tmp/mgmtdspawn.*
sudo rm -rf /tmp/mgmtdtest.*
sudo rm -rf /tmp/xcalar
sudo rm -rf /tmp/valgrindCheck.*
sudo find /tmp/ -type f -name "childnode*" -delete
sudo rm -rf /var/tmp/xcalar-$LOGNAME
sudo rm -rf /var/tmp/xcalar
sudo rm -rf /var/tmp/xcalarTest-$LOGNAME
sudo rm -rf /var/tmp/xcalarTest
sudo rm -rf /var/opt/xcalar
sudo rm -rf /var/opt/xcalarTest
sudo rm -rf $shm/xcalar-shm-*
sudo rm -rf /tmp/xcalar/xcalar-shm-*
sudo mkdir -p /opt/xcalar
test -e /etc/xcalar || sudo mkdir -p /etc/xcalar
mkdir /var/tmp/xcalar
mkdir /var/tmp/xcalarTest-$LOGNAME
mkdir /var/tmp/xcalarTest
mkdir -p /tmp/xcalar
sudo mkdir -p /var/opt/xcalar /var/opt/xcalarTest
sudo chown $(id -u):$(id -g) /var/opt/xcalar /var/opt/xcalarTest

set -e

if [ "$DeployType" = "Source" ]; then
    export XLRDIR=`pwd`
    export PATH=$XLRDIR/bin:$XLRDIR/bin/statcollector:$PATH
    export GenConfig="$XLRDIR/bin/genConfig.sh"
    build clean
    if [ "$BuildType" = "prod" ]; then
        build prod
    else
        build config
        build
    fi
elif [ "$DeployType" = "Installer" ]; then
    set +e
    sudo rm $XCE_CONFIG # To stop it from umounting the shared directory
    sudo yum -y remove xcalar
    set -e
    sudo $INSTALLER_PATH
    exit 0
fi

sudo pip install supervisor==3.3.1

set +e

if [ ! -e "$XcalarRootCompletePath" ]; then
    sudo mkdir -p $XcalarRootCompletePath
fi

sudo umount $XcalarRootCompletePath

sudo mount $NfsServer:$NfsPath $XcalarRootCompletePath


if [ "$DeployType" != "None" ]; then
    if [ "$XcalarRootCompletePath" != "" ]; then
        sudo rm -rf $XcalarRootCompletePath/sessions
    fi
fi

set -e

sudo sed --in-place '/\dev\/shm/d' /etc/fstab

tmpFsSizeGb=`cat /proc/meminfo | grep MemTotal | awk '{ printf "%.0f\n", $2/1024/1024 }'`

#let "tmpFsSizeGb = $tmpFsSizeGb * ($BufferCachePercentOfTotalMem + $UdfBufferCachePercentOfTotalMem) / 100"
let "tmpFsSizePct = $BufferCachePercentOfTotalMem + $UdfBufferCachePercentOfTotalMem"

echo "none  /dev/shm    tmpfs   defaults,size=${tmpFsSizePct}%  0   0" | sudo tee -a /etc/fstab

sudo mount -o remount /dev/shm

if [ -f $XCE_CONFIG ]; then
    sudo rm $XCE_CONFIG
fi

set +e
sudo cp -rfR $XLRDIR/bin/* $XLROPTDIR/bin/
set -e


if [ ! -d $XLROPTDIR/lib/python2.7/ ]; then
    sudo mkdir -p $XLROPTDIR/lib/python2.7/
fi

sudo rm -rf $XLRDIR/lib/python2.7/pyClient.zip
sudo rm -rf $XLRDIR/lib/python2.7/pyClient

sudo cp -rf ./src/bin/pyClient/pyClient.zip $XLROPTDIR/lib/python2.7/
sudo unzip -o $XLROPTDIR/lib/python2.7/pyClient.zip

if [ ! -f /etc/xcalar/template.cfg ]; then
    sudo cp -rf $XLRDIR/src/data/template.cfg /etc/xcalar/template.cfg
fi

sudo $GenConfig /etc/xcalar/template.cfg $XCE_CONFIG $xcalarNodes

sudo sed -i -e "s'Constants\.XcalarRootCompletePath=.*'Constants\.XcalarRootCompletePath=$XcalarRootCompletePath'" $XCE_CONFIG

echo "$Configuration" | sudo tee -a $XCE_CONFIG

if [ ! -f /etc/xcalar/supervisor.conf ]; then
    sudo cp -rf $XLRDIR/conf/supervisor.conf /etc/xcalar/supervisor.conf
fi

if [ ! -f /var/tmp/xcalar-root ]; then
    mkdir -p /var/tmp/xcalar-root
fi

sudo cp -rf $XLRDIR/bin/xcalarctl /etc/init.d/xcalarctl

sudo $XLRDIR/bin/installer/user-installer.sh start

if [ -f /usr/bin/journalctl ]; then
    sudo journalctl -f -p0..4
else
    tail -f /var/log/Xcalar.log
fi

echo "Done with StartCluster"
