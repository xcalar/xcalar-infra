#!/bin/bash

export PATH="$XLRDIR/bin:$PATH"
TestList=$1
configFile="${2:-$XLRDIR/src/bin/usrnode/test-config.cfg}"
ScriptPath="${3:-startFuncTests.py}"
numNode="${4:-2}"
target="${5:-/netstore/users/xma/dashboard}"

TestStr=""
TestArray=(${TestList//,/ })
for Test in "${TestArray[@]}"
do
TestStr="$TestStr --testCase $Test"
done

cd $XLRDIR

ps aux | grep "[u]srnode"
if [ $? -eq 0 ]; then
    xccli -c "shutdown"
    sleep 10s
fi

build clean
build config
if [ $? -ne 0 ]; then
    echo "build config failed"
    exit 1
fi

build

if [ $? -ne 0 ]; then
    echo "build config failed"
    exit 1
fi

source $XLRDIR/doc/env/xc_aliases

xclean &> /dev/null

for ii in `seq 0 $((numNode - 1))`;
do
    LD_PRELOAD=$XLRDIR/src/lib/libfaulthandler/.libs/libfaulthandler.so.0 $XLRDIR/src/bin/usrnode/usrnode -f $configFile -i $ii -n $numNode  &> /dev/null &
done

timeOut=600
counter=0
set +e
while true; do

    xccli -c "version" | grep "Backend Version"

    if [ $? -eq 0 ]; then
        break
    fi

    sleep 5s
    counter=$(($counter + 5))
    if [ $counter -gt $timeOut ]; then
        echo "usrnode time out"
        exit 1
    fi
done
set -e

echo "usrnode ready"

python2.7 $ScriptPath $TestStr --target $target --cliPath $XLRDIR/bin/xccli --cfgPath $configFile 2>&1 </dev/null &
