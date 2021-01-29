#!/bin/bash

NUM_INSTANCES=${NUM_INSTANCES:-1}
PARAMETERS="${PARAMETERS:-parameters.json}"
test $# -gt 0 || set -- $PARAMETERS

if [ "$1" == -h ] || [ "$1" == --help ]; then
    echo >&2 "usage: $0 [<license.txt or long-license-string> default: parse $PARAMETERS] [<number of instances>: default $NUM_INSTANCES]"
    exit 1
fi

if test -f "$1"; then
    if echo $1 | grep -q '.json$'; then
        if [ "$(jq -r .parameters < $1)" != null ]; then
            PREFIX=".parameters"
        fi
        if ! LICENSE="$(jq -r ${PREFIX}.licenseKey.value $1 2>/dev/null)" || [ "$LICENSE" = null ]; then
            echo >&2 "ERROR: Unable to parse licenseKey from $1"
            exit 1
        fi
        if ! NUM_INSTANCES="$(jq -r ${PREFIX}.scaleNumber.value $1 2>/dev/null)" || [ "$NUM_INSTANCES" = null ]; then
            NUM_INSTANCES=1
        fi
    else
        LICENSE="$(cat $1)"
    fi
elif test -n "$1"; then
    LICENSE="$1"
    NUM_INSTANCES="$2"
else
    echo >&2 "ERROR: Need to specify params.json or license on the command line"
    exit 1
fi

curl -4 --location --retry 20 --retry-delay 3 --retry-max-time 60 \
		-sH 'Content-Type: application/json' -X POST \
		-d '{ "licenseKey": "'$LICENSE'", "numNodes": '${NUM_INSTANCES:-1}', "installerVersion": "latest" }' \
		https://zqdkg79rbi.execute-api.us-west-2.amazonaws.com/stable/installer | jq -r .
