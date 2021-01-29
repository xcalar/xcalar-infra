#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
export XLRINFRADIR="$(cd $DIR/.. && pwd)"
export PATH=$XLRINFRADIR/bin:$PATH

rc=0
for FILE in "$@"; do
    desc="$(file $FILE)"
    if [[ "$desc" =~ "shell script" ]]; then
        echo >&2 "Checking $FILE ..."
        if ! shellcheck -S info "$FILE"; then
            if ! shellcheck -S error "$FILE" >/dev/null 2>&1; then
                echo >&2 "ERROR: shellcheck **** $FILE ****"
                rc=1
            fi
        fi
    elif echo "$FILE" | grep -q '\.json$'; then
        echo >&2 "Checking $FILE for valid json ..."
        if ! jq -r . "$FILE" >/dev/null; then
            echo >&2 "ERROR: jq failed **** $FILE ****"
            rc=1
        fi
    fi
done
exit $rc
