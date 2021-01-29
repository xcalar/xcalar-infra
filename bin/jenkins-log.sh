#!/bin/bash

JOBS_LOG_CACHE=${JOBS_LOG_CACHE-/netstore/infra/jenkins/jobs_log_cache}
JENKINS_SSH=${JENKINS_SSH:-jenkins@jenkins.int.xcalar.com}

set -o pipefail

strjoin() {
    local IFS="$1"
    shift
    echo "$*"
}

jenkins_log() {
    local job_build=($(echo "$1" | sed -r 's@.*job/([A-Za-z0-9_\.-]+)/([0-9]+).*$@\1 \2@'))
    local log_cache
    if [ -n "$JOBS_LOG_CACHE" ]; then
        local log_cache=$(strjoin / ${JOBS_LOG_CACHE} "${job_build[@]}")
        if test -e "${log_cache}/log"; then
            if cat "${log_cache}/log"; then
                return
            fi
        fi
    fi
    local tmp=$(mktemp -t jenkins-log.XXXXXX)
    if ssh $JENKINS_SSH "cat jobs/${job_build[0]}/builds/${job_build[1]}/log" | tee "$tmp"; then
        if [ -n "$log_cache" ] && mkdir -p "$log_cache" 2>/dev/null; then
            mv "$tmp" "${log_cache}/log"
        fi
        rm -f "$tmp"
        return 0
    fi
    rm "$tmp"
    return 1
}

usage() {
    cat <<EOF
    usage: $0 job-url

    job-url         A url to a job such as http://jenkins-url/job/SomeJob/30, or a partial url such as:

                    job/SomeJob/30
                    https://jenkins.int.xcalar.com/job/GerritXCETest/15287/
EOF
}

case "$1" in
    http://*) jenkins_log "$1" ;;
    https://*) jenkins_log "$1" ;;
    job/*) jenkins_log "$1" ;;
    *)
        usage
        exit 1
        ;;
esac
exit $?
