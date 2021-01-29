#!/bin/bash

DEBUG=0

debug() {
    if ((DEBUG)); then
        echo >&2 "debug: $@"
    fi
    "$@"
}

latest_installer() {
    local QUERY="ReleaseCandidates/xcalar-*/*/"
    local BUILD_TYPE="prod"
    local BASE="/netstore/builds"
    local LATEST=true

    local cmd result
    while [ $# -gt 0 ]; do
        cmd="$1"
        shift
        case "$cmd" in
            --query=*) QUERY="${cmd#--query=}";;
            --type=*) BUILD_TYPE="${cmd#--type=}";;
            --base-dir=*)

                BASE="${cmd#--base-dir=}"
                QUERY='*'
                ;;
            -h|--help) usage;;
            --all) LATEST=false;;
            --debug) DEBUG=1;;
            -*) echo >&2 "Unknown flag: $cmd"; exit 1;;
            *) echo >&2 "Unknown parameter: $cmd"; exit 1;;
        esac
    done

    if $LATEST; then
        debug ls -t ${BASE}/${QUERY}/${BUILD_TYPE}/xcalar-*-installer | head -1
    else
        debug ls -t ${BASE}/${QUERY}/${BUILD_TYPE}/xcalar-*-installer
    fi
}

if [[ $(basename $(readlink -f $0)) == $(basename $(readlink -f ${BASH_SOURCE[0]})) ]]; then
    latest_installer "$@"
fi
