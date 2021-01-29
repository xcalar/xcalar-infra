#!/bin/bash

TTL="${TTL:-120}"
ZONE="${ZONE:-xcalar-cloud}"
DOMAIN="${DOMAIN:-xcalar.cloud}"
DRYRUN="${DRYRUN-1}"

usage() {
    echo "Usage: $0 (add|remove) NAME1 IP1 NAME2 IP2 ..."
    echo
    echo "Set the following variables to control which zone/domain to update"
    echo
    echo " TTL=$TTL"
    echo " ZONE=$ZONE"
    echo " DOMAIN=$DOMAIN"
    echo " DRYRUN=$DRYRUN"
    echo
    exit 1
}

gdnsr() {
    if [ "$DRYRUN" = 1 ]; then
        echo "dry-run: gcloud dns record-sets $* --zone ${ZONE}"
    else
        (
            set -x
            gcloud dns record-sets "$@" --zone "${ZONE}"
        )
    fi
}

gdnst() {
    gdnsr transaction "$@"
}

update() {
    local record
    record=($(gcloud dns record-sets list --zone $ZONE | grep "^${1}.${DOMAIN}" | awk '{printf "%s\n%s\n",$3,$4}'))
    if [ ${#record[@]} -eq 2 ]; then
        gdnst remove "${record[1]}" --name "${1}.${DOMAIN}" --ttl "${record[0]}" --type A
    fi
    gdnst add "${2}" --name "${1}.${DOMAIN}" --ttl "${TTL}" --type A
}

abort() {
    gdnst abort
    echo >&2 "ERROR: Aborted gcloud dns transaction: $*"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

OP="${1}"
shift

case "$OP" in
    -h | --help) usage ;;
    add) ;;
    remove) ;;
    update) ;;
    *)
        echo >&2 "Operation must be add, remove or update"
        exit 1
        ;;
esac

set -e
if [ -e transaction.yaml ]; then
    NOW=$(date +%s)
    echo >&2 "WARNING: transaction.yaml exists. Saving to transaction-${NOW}.yaml"
    mv transaction.yaml transaction-${NOW}.yaml
fi
gdnst start

set +e

while [ $# -ge 2 ]; do
    case "$OP" in
        add | remove) gdnst "$OP" "$2" --name "${1}.${DOMAIN}" --ttl "$TTL" --type A ;;
        update) update "$1" "$2" ;;
    esac
    shift 2
done
gdnst execute
rc=$?
exit $rc
