#!/bin/bash -x

touch /tmp/${JOB_NAME}_${BUILD_ID}_START_TIME

export XLRDIR=/opt/xcalar
export PATH=$XLRDIR/bin:$PATH
export XCE_CONFIG=`pwd`/default.cfg
export XCE_USER=`id -un`
export XCE_GROUP=`id -gn`

restartXcalar() {
    xcalar-infra/functests/launcher.sh $memAllocator
}

if [ $MemoryAllocator -eq 2 ]; then
    memAllocator=2
else
    memAllocator=0
fi

set +e
find /var/opt/xcalar -type f -not -path "/var/opt/xcalar/support/*" -delete
rm -rf /var/opt/xcalar/kvs/
rm -rf /var/opt/xcalar/published/
find . -name "core.childnode.*" -type f -delete

set -e
sudo -E yum -y remove xcalar

sudo -E $INSTALLER_PATH --noStart

rm $XCE_CONFIG
$XLRDIR/scripts/genConfig.sh /etc/xcalar/template.cfg $XCE_CONFIG `hostname`

restartXcalar || true

if xccli -c version 2>&1 | grep -q 'Error'; then
    echo "Could not even start usrnodes after install"
    exit 1
fi

gitsha=`xccli -c "version" | head -n1 | cut -d\  -f3 | cut -d- -f5`
echo "GIT SHA: $gitsha"

options="--user $XCALAR_USER \
        --env $TARGET_ENV \
        --exportUrl $EXPORT_URL --bases \
        --updates --db $DB \
        --numBaseRows $NUM_BASE_ROWS \
        --numUpdateRows $NUM_UPDATE_ROWS \
        --numUpdates $NUM_UPDATES \
        --updateSleep $UPDATE_SLEEP \
        --dbHost $DB_HOST --dbPort $DB_PORT \
        --dbUser $DB_USER --dbPass $DB_PASS"

if $VALIDATE_DATA ; then
    options="$options --validateData"
fi

$XLRDIR/bin/python3 xcalar-infra/imdTests/genIMD.py $options

pkill -9 usrnode
pkill -9 childnode
pkill -9 xcmonitor
pkill -9 xcmgmtd
sleep 60
