#!/bin/bash

# This file is copied to each node on the cluster and sourced via .bashrc so
# these functions are available to the test orchastrator via rcmd.

dumpNodeOSStats() {
    echo "================ Stats for $(hostname) ================"

    free -h
    vmstat -s

    local pidList=$(pgrep -f 'usrnode|childnode|xcmgmtd|xcmonitor|xcalar-sqldf|expServer')
    local psfmt="pid,%cpu,%mem,vsz,rss,stat,lstart,cmd"
    ps -ww -o"$psfmt" -p 1
    for pid in $pidList
    do
        ps -hww -o"$psfmt" -p $pid
    done

    for pid in $pidList
    do
        cat /proc/$pid/status |grep 'Vm\|Rss\|Name\|^Pid:' |tr '\n' ',' |tr '\t' ' ' |tr -s ' '
        echo
    done
}
