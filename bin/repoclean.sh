#!/bin/bash

usage() {

    cat <<EOF
    usage: $0 [-C|--directory> DIR]

    Print names of older rpm version in current directory

    -C, --directory DIR         Change PWD to DIR before executing
    -o, --output TAR            Remove old rpms and place into tar file
    - Ser

    $0 | tar czvf ../oldpackages.tar --remove-files -T -
EOF
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -h|--help) usage; exit 0;;
        -C|--directory) cd "$1" || exit 1; shift;;
        *) usage >&2; exit 1;;
    esac
done

TMPDIR=$(mktemp -d /tmp/packages.XXXXXX)
TMP=${TMPDIR}/packages.txt

for ii in *.rpm; do
    rpm -qp $ii --qf '%{NAME}\n'
done | sort | uniq > $TMP
for ii in $(< $TMP); do
    ls -rt "${ii}"-[0-9]*.rpm | head -n -1
done

rm -rf $TMPDIR
