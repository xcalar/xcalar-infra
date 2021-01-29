#!/bin/bash

KEEPON_RETRY=${KEEPON_RETRY:-10}
KEEPON_DELAY=${KEEPON_DELAY:-2}

do_retry() {
    until "$@"; do
        [ ${KEEPON_RETRY} -gt 0 ] || exit 1
        KEEPON_RETRY=$((KEEPON_RETRY-1))
        sleep $KEEPON_DELAY
    done
}

[ $# -gt 0 ] || set -- --help

while [ $# -gt 0 ]; do
    cmd="$1"
    case "$cmd" in
        -h|--help)
            echo >&2 "usage: $0 [--retry N (default: $KEEPON_RETRY)] [--delay N (default: $KEEPON_DELAY)] [--] cmd args ..."
            echo >&2 ""
            exit 1
            ;;
        --retry)
            KEEPON_RETRY="$2"
            shift 2
            ;;
        --delay)
            KEEPON_DELAY="$2"
            shift 2
            ;;
        --) shift
            break
            ;;
        *)  break
            ;;
    esac
done

do_retry "$@"
