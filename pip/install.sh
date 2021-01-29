#!/bin/bash
set -eu

DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

deactivate 2> /dev/null || true

do_bundle() {
    [ $# -gt 0 ] || set -- -r requirements.txt
    TMPENV=$TMPDIR/venv
    python3 -m venv $TMPENV
    $TMPENV/bin/python3 -m pip install -U pip setuptools wheel
    . $TMPENV/bin/activate
    pip download -d ${PACKAGES} "$@"
    pip wheel -w "$WHEELS" --no-index --no-cache-dir --find-links file://${PACKAGES}/ "$@"
}

do_install() {
    [ $# -gt 0 ] || set -- -r requirements.txt
    pip3 install --no-index --no-cache-dir --find-links file://${DIR}/wheels/ "$@"
}

main() {
    local install='' bundle=''
    local output
    declare -a reqs=()

    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            install) install=1 ;;
            bundle) bundle=1 ;;
            -r | --requirements)
                req="$1"
                shift
                ;;
            -o | --output)
                output="$1"
                shift
                ;;
            *)
                echo >&2 "ERROR: Unknown command: $cmd"
                exit 1
                ;;
        esac
    done

    #if [ $((bundle + install)) -eq 0 ]; then
    #    test -d wheel && install=1 || bundle=1
    #fi
    if [ $((bundle + install)) != 1 ]; then
        echo >&2 "ERROR: Must specify 'bundle' or 'install'"
        exit 2
    fi

    if ((install)); then
        if [ -n "${VIRTUAL_ENV:-}" ] || [ $(id -u) -eq 0 ]; then
            user_install=''
        else
            user_install='--user'
        fi
        args=''
        reqs=()
        for req in *.txt; do
            reqs+=("$req")
        done
        do_install -r "${reqs[@]}"
    fi
    if ((bundle)); then
        TMPDIR=$(mktemp -d /tmp/pip.XXXXXX)
        PACKAGES=$TMPDIR/packages
        WHEELS=$TMPDIR/wheels
        mkdir -p "$PACKAGES" "$WHEELS"
        echo >&2 "Building packages from $req ..."
        do_bundle -r $req
        cp $req $TMPDIR/
        cp ${BASH_SOURCE[0]} $TMPDIR/
        echo >&2 "Creating $output ..."
        tar czf $output -C "${TMPDIR}" $(basename ${BASH_SOURCE[0]}) $(basename $req) wheels
        rm -rf $TMPDIR
    fi
}

main "$@"
