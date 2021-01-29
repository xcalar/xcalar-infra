#!/bin/bash

if [ $# -lt 2 ]; then
    set -- careers /netstore/infra/xcalar.com/logs/monthly/xcalar.com-$(date +'%b-%Y').gz
    echo >&2 "Didn't specify log file, using '$*' ..."
fi

cat_logs () {
    while [ $# -gt 0 ]; do
        if echo "$1" | grep -q '\.gz$'; then
            zcat "$1"
        else
            cat "$1"
        fi
        shift
    done
}

SEARCH="$1"
shift

cat_logs "$@" | grep -v 'Googlebot' | awk "/$SEARCH/{print \$1}" | grep -v 'Googlebot' | sort | uniq -c | sort -rn | awk '$1 > 1 {print}'
