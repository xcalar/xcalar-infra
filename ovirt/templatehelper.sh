#!/bin/bash

set -e

##
#
# Sets up default.cfg file
#
# for single node:
#	./templatehelper.sh nodeIP
#
# for cluster of nodes:
#	./templatehelper.sh <shared cluster dir> <node0 IP> <node1 ip> ... <nodeN ip>
#
##

genconfigscript='/opt/xcalar/scripts/genConfig.sh'
templatefile='/etc/xcalar/template.cfg'
fileloc='/etc/xcalar/default.cfg'

NUM_ARGS=$#
if [ $NUM_ARGS -eq 1 ]; then
    $genconfigscript $templatefile - localhost > $fileloc
else
    echo "This is for a cluster configuration..." >&2
    SHARED_CLUSTER_DIR="$1"
    shift
    $genconfigscript $templatefile - $@ > $fileloc # do not preserve whitespace in IP list when calling genConfig
    # replace XcalarRootCompletePath default value to cluster dir passed in
    CLUSTER_VAR=Constants.XcalarRootCompletePath
    CLUSTER_VAR_DEFAULT=$(grep -oP "(?<=$CLUSTER_VAR=)"\\S* $fileloc)
    sed -i s@$CLUSTER_VAR_DEFAULT@$SHARED_CLUSTER_DIR@g $fileloc
fi
