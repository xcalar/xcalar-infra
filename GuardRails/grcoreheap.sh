#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [[ "$#" -ne 3 ]]
then
    echo "Usage: $0 binary_file core_file output_file" 1>&2
    exit 1
fi

binf=$(readlink -f "$1")
coref=$(readlink -f "$2")
of=$(readlink -f "$3")

cd "$SCRIPT_DIR"
gdb -n -batch -ex 'set pagination off' -ex 'source grgdb.py' -ex 'gr-dump-in-flight' "$binf" "$coref" |sed '1,/^===== START TRACES =====/d' > "$of"
