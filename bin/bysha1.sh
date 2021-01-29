#!/bin/bash

bysha1 () {
    sha1sum "$1" | cut -d' ' -f1
}

usage () {
    echo >&2 "usage: $0 [-p prefix] file1 ..."
    exit 1
}

while getopts "hp:" opt; do
    case $opt in
        p) PREFIX="$OPTARG";;
        h) usage;;
        --) break;;
        *) echo >&2 "ERROR: Unknown argument $opt"; usage;;
    esac
done

shift $((OPTIND-1))

for ARG in "$@"; do
    DIR="$(dirname "$ARG")"
    BN="$(basename "$ARG")"
    echo "${PREFIX}$(bysha1 "${ARG}")/${BN}"
done
