#!/bin/bash

set +e

NAME="$(basename ${BASH_SOURCE[0]})"

export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}

usage() {
    cat <<EOF >&2
    usage: $NAME {start|stop} vm-name ...

    example:

    $NAME start myvm-1
    $NAME stop myvm-1
EOF
    exit 1
}

gce_instances() {
    local cmd="$1"
    local rc=1
    shift
    if [ $# -gt 1 ]; then
        gcloud compute instances "$cmd" "$@"
        rc=$?
    else
        if gcloud compute instances describe "$1" &>/dev/null; then
            gcloud compute instances "$cmd" "$@"
            rc=$?
        else
            local -a INSTANCES=($(gcloud compute instances list | awk '/^'${1}'-[1-9][0-9]*/{print $1}'))
            if [ ${#INSTANCES[@]} -eq 0 ]; then
                echo >&2 "No instances or cluster named $1 found"
                exit 1
            fi
            gcloud compute instances "$cmd" "${INSTANCES[@]}"
            rc=$?
        fi
    fi
    if [ $rc -ne 0 ]; then
        logger -t "$NAME" -i -s "[ERROR:$rc] gcloud compute instances $*"
    else
        logger -t "$NAME" -i -s "[OK] gcloud compute instances $*"
    fi
    return $rc
}

if [ -z "$1" ]; then
    usage
fi

cmd="$1"
case "$cmd" in
    -h | --help) usage ;;
    start) ;;
    stop) ;;
    list) ;;
    *) usage ;;
esac
shift

gce_instances "$cmd" "$@"
exit $?
