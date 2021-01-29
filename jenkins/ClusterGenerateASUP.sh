#!/bin/bash
set -e
set -x

say () {
    echo >&2 "$*"
}

say "$0 START ===="

if [ -z $CLUSTER ]; then
    say "ERROR: CLUSTER cannot be empty"
    exit 1
fi
if [ -z $VmProvider ]; then
    say "ERROR: VmProvider cannot be empty"
    exit 1
fi

export XLRINFRADIR="${XLRINFRADIR:-${XLRDIR}/xcalar-infra}"
source "${XLRINFRADIR}/bin/clusterCmds.sh"
initClusterCmds
genSupport "${CLUSTER}"

say "$0 END ===="
exit 0
