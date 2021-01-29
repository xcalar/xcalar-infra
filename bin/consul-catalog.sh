#!/bin/bash
#
# Queries consul catalog for nodes with matching meta-data
#
# Example usecase: Generate dynamic inventory for ansible:
#
#  $ consul-catalog.sh -a --role=jenkins_slave
#
# [role_jenkins_slave]
# customer-11-1                             ansible_host=10.10.7.139
# customer-11-3                             ansible_host=10.10.4.59
# ...



declare -a ARGS=()
ANSIBLE=0
YAML=0

parse_args() {

    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            -a|--ansible) ANSIBLE=1;;
            --role=*) ARGS+=("-node-meta=role=${cmd#--role=}"); HEADING="role_${cmd#--role=}";;
            --cluster=*) ARGS+=("-node-meta=cluster=${cmd#--cluster=}"); HEADING="cluster_${cmd#--role=}";;
            --role) ARGS+=("-node-meta=${cmd#--}=$1"); HEADING="role_${1}"; shift;;
            --cluster) ARGS+=("-node-meta=${cmd#--}=$1"); HEADING="cluster_${1}"; shift;;
            -y|--yaml) YAML=1;;
            --details|-detailed) ARGS+=(-detailed);;
            --hosts) HOSTS_ONLY=1;;
            *) echo >&2 "ERROR: Unknown argument: $cmd"; exit 1;;
        esac
    done
}

parse_args "$@"

if ((ANSIBLE)); then
    if ((YAML)); then
        echo "---"
        echo "all:"
        echo "  hosts:"
        consul catalog nodes "${ARGS[@]}" | tail -n+2 | awk '{printf "    %s:\n      ansible_host: %s\n",$1,$3}'
        echo "  vars:"
        echo "    myvar: value"
        echo "  children:"
        echo "    ${HEADING}:"
        consul catalog nodes "${ARGS[@]}" | tail -n+2 | awk '{printf "      %s:\n        ansible_host: %s\n",$1,$3}'

    else
        [ -n "$HEADING" ] && echo "[$HEADING]" || :
        consul catalog nodes "${ARGS[@]}" | tail -n+2 | awk '{printf "%s\t\t\tansible_host=%s\n",$1,$3}'
    fi
elif ((HOSTS_ONLY)); then
    set -o pipefail
    consul catalog nodes "${ARGS[@]}" | awk '{print $1}' | tail -n+2
else
    consul catalog nodes "${ARGS[@]}"
fi
