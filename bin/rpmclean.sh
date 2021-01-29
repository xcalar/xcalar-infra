#!/bin/bash

PRUNE=0
REPORT=0
while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -C|--chdir) cd "$1" || exit 1; shift;;
        --prune) PRUNE=1;;
        --report) REPORT=1;;
        -h|--help)
            echo "usage: $0 [-C|--chdir dir] [--prune] [--report]"
            exit 0
            ;;
        *)
            echo >&2 "ERROR: Unknown argument: $cmd"
            exit 2
            ;;
    esac
done

mbused() {
    local mb
    if mb=$(du -BM -sc "$@" | tail -1 | awk '{print $1}'); then
        echo "${mb%M}"
        return 0
    fi
    return 1
}

# Run in a directory with rpms. Prints a list of the
# latest rpms to keep, letting  you discard the rest.
tmpfile=$(mktemp -t rpmcleanXXXXXX)
(
for ii in *.rpm; do
    rpm -qp $ii --qf "%{NAME} %{VERSION}-%{RELEASE} $ii\n"
done
) > $tmpfile
if ! test -s $tmpfile; then
    echo >&2 "Please run in a directory with versioned rpms"
    exit 1
fi

longest=0
for ii in $(awk '{print $1}' $tmpfile); do
    if [ "${#ii}" -gt $longest ]; then
        longest=${#ii}
    fi
done

sort -Vr -k3 < $tmpfile | column -t | uniq -w $longest | sort | tee ${tmpfile}2
awk '{print $(NF)}' < ${tmpfile}2 > ${tmpfile}3
if ((REPORT)); then
    size=$(mbused -- *.rpm)
    newsize=$(mbused $(cat ${tmpfile}3))
    delta=$((size - newsize))
    echo "Current: ${size}M"
    echo "New: ${newsize}M"
    echo "Save: ${delta}M"
fi

if ((PRUNE)); then
    tmpdir=.tmp$$
    mkdir -p $tmpdir
    awk '{print $(NF)}' < ${tmpfile}2 | xargs -r -n1 -I{} ln '{}' $tmpdir/'{}'
    rm -f -- *.rpm
    mv $tmpdir/* .
    rmdir $tmpdir
fi

rm ${tmpfile}*


