#!/bin/bash
#
# Shellcheck does static code analysis of shell scripts.
#
# Usage:
#   $ shellcheck.sh myscript.sh
#
set -e

SHELLCHECK_IMAGE='koalaman/shellcheck@sha256:adccaae3037f6e89793c16ecc728a60a5d35cee24bb50f70a832dc325c87a2a5'

if test $# -eq 1 && test -d "$1"; then
    DIR="$1"
    shift
    SCRIPTS=()

    while IFS= read -r -d '' FILE; do
        if file "$FILE" | grep -q 'shell script'; then
            SCRIPTS+=("$FILE")
        fi
    done < <(find "$DIR" -type f)

    if [ ${#SCRIPTS[@]} -gt 0 ]; then
        set -- "${SCRIPTS[@]}"
    fi
fi

if test $# -eq 0; then
    echo >&2 "Usage: $0 [shellcheck options] script... or dir"
    exit 1
fi

if [ -n "$SHELLCHECK_EXCLUDES" ]; then
    SHELLCHECK_EXCLUDES="SC2086,${SHELLCHECK_EXCLUDES}"
else
    SHELLCHECK_EXCLUDES="SC2086"
fi

set +e
ERRORS=0
while [ $# -gt 0 ]; do
    cmd="$1"
    case "$cmd" in
        --update)
            docker pull $SHELLCHECK_IMAGE
            shift
            ;;
        --)
            shift
            break
            ;;
        *) break ;;
    esac
done

for FILE in "$@"; do
    docker run -v "${PWD}:${PWD}:ro" -w "$PWD" --rm \
        ${SHELLCHECK_IMAGE} \
        --shell=bash \
        --exclude=${SHELLCHECK_EXCLUDES} \
        --color=always \
        --severity=error \
        "$FILE"
    rc=$?
    if [ $rc != 0 ]; then
        echo "FAILED:($rc): $FILE"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK: ${FILE}"
    fi
done
if [ $ERRORS -gt 0 ]; then
    echo >&2 "ERROR: $ERRORS files failed"
    exit 1
fi
exit 0
