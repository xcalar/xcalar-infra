#!/bin/bash
#
# Use
#   $ ./pip-bundler.sh bundle [-o output.tar.gz] [--] <pip-commands ...>
#
# To generate a bunlde containing the packages fetched
# from the command. Eg, ./INSTALL.sh bundle -r requirements.txt
# will bundle all the packages into wheel.zip, including
# this same script that can be called "on the other side" to
# ./myreq/install.sh install -r requirements.txt

set -eu

DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
USER_INSTALL=""
INSTALL=0
BUNDLE=0
DEBUG=${DEBUG:-0}

say() {
    echo >&2 "$@"
}

trace() {
    if ((DEBUG)); then
        say "debug:" "$@"
    fi
    eval "$@"
}

info() {
    say "info: $*"
}

die() {
    local rc=1
    if [ $# -gt 1 ]; then
        rc="$1"
        shift
    fi
    say "ERROR: $*"
    exit $rc
}

pip() {
    trace $VIRTUAL_ENV/bin/python3 -m pip "$@"
}

newvenv() {
    $PY3 -m venv "$1" >&2 \
        && $1/bin/python3 -m pip install -U pip >&2 \
        && $1/bin/python3 -m pip install -U setuptools wheel pip-tools >&2 \
        && . "$1"/bin/activate \
        && hash -r \
        && echo "$1"
}

do_bundle() {
    ARGS=()
    if [ $# -eq 0 ]; then
        if test -e requirements.txt; then
            ARGS+=(-r requirements.txt)
        fi
        if test -e constraints.txt; then
            ARGS+=(-c constraints.txt)
        fi
    fi
    if test -d /netstore/infra/wheels; then
        ARGS+=(--find-links http://netstore/infra/wheels/py${PYVER}/index.html --find-links file:///netstore/infra/wheels/index.html --trusted-host netstore --trusted-host netstore.int.xcalar.com)
    fi

    deactivate 2>/dev/null || true
    VENV=$TMPDIR/venv
    newvenv "$VENV"
    . $VENV/bin/activate
    hash -r
    pip wheel -w "$WHEELS" "${ARGS[@]}" "$@"
}

do_install() {
    ${PIP} install --no-index --no-cache-dir --find-links file://${DIR}/wheels/ "$@"
}

sha256() {
    if command -v sha256sum >/dev/null; then
        sha256sum | cut -d' ' -f1
    else
        shasum -a 256 | cut -d' ' -f1
    fi
}

usage() {
    echo "usage: $1 [install|bundle] [--python /path/to/py3] [--pip /path/to/pip3] bundle.zip [regular pip-options]"
}

main() {
    local output=''

    BUNDLE=1
    if [[ $0 =~ install ]]; then
        INSTALL=1
        BUNDLE=0
    fi

    export TMPDIR="${TMPDIR:-/var/tmp/$(id -u)/pip-bundle}"
    # shellcheck disable=SC2064
    mkdir -p $TMPDIR/wheels $TMPDIR/cache
    rm -rf $TMPDIR/venv-$$

    export PATH=$PATH:/opt/xcalar/bin
    hash -r
    PY3="$(which python3)"
    output='pip-bundler.tar.gz'
    install_target=''
    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            install) INSTALL=1 ;;
            bundle) BUNDLE=1 ;;
            -h | --help)
                usage
                exit 0
                ;;
            -r | --requirements)
                req="$1"
                shift
                ;;
            -c | --constraints)
                con="$1"
                shift
                ;;
            -i | --install)
                install_links="$1"
                shift
                ;;
            -t | --target)
                install_target="$1"
                shift
                ;;
            -o | --output)
                output="$1"
                shift
                ;;
            --pip)
                PIP="$1"
                shift
                ;;
            -p | --python)
                PY3="$1"
                shift
                ;;
            --) break ;;
            *)
                usage >&2
                die 2 "Unknown command: $cmd"
                ;;
        esac
    done
    if [ -z "${PIP:-}" ]; then
        PIP="$PY3 -m pip"
    fi
    PYVER="$($PY3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
    if [ -n "$output" ]; then
        output="$(readlink -f $output)"
    fi

    if [ -z "${req:-}" ]; then
        if test -e "requirements.txt"; then
            req=requirements.txt
        elif test -e "requirements.in"; then
            req=requirements.in
        else
            die 2 "Must provide -r requirements.txt or .in"
        fi
    fi
    if [[ $req =~ .in$ ]]; then
        (
            VENV=$(mktemp -d -t venv.XXXXXX)
            newvenv $VENV
            . $VENV/bin/activate
            pip-compile -o $(basename $req .in)_constraints.txt $req
            rm -rf $VENV
        )
    fi

    if [ -z "${con:-}" ]; then
        test -e "constraints.txt" && con=constraints.txt || con=''
    fi

    if [ $((BUNDLE + INSTALL)) != 1 ]; then
        die 2 "Must specify 'bundle' or 'INSTALL'"
    fi

    if ((INSTALL)); then
        if [ -n "$install_target" ]; then
            deactivate 2>/dev/null || true
            USER_INSTALL="-t $install_target"
            if ! test -d "$install_target"; then
                mkdir -p "$install_target" || die 2 "Failed to create $install_target"
            fi
            cp requirements.txt constraints.txt $install_target
            PIP="${PIP:-$PY3 -m pip}"
            PIP_ARGS=(-t $install_target --no-index --no-cache-dir --find-links file://${DIR}/wheels/ ${con:+-c $con})
            $PIP install "${PIP_ARGS[@]}" -U setuptools \
                && $PIP install "${PIP_ARGS[@]}" ${req:+-r $req} ${con:+-c $con} \
                && exit 0
            exit 1
        elif [ -n "${VIRTUAL_ENV:-}" ] || [ $(id -u) -eq 0 ]; then
            USER_INSTALL=''
        else
            USER_INSTALL='--user'
        fi
        do_install $USER_INSTALL -U pip
        do_install $USER_INSTALL -U setuptools
        do_install $USER_INSTALL -U wheel ${con:+-c $con}
        do_install $USER_INSTALL -r ${req} ${con:+-c $con}
    elif ((BUNDLE)); then
        PACKAGES=$TMPDIR/packages
        WHEELS=$TMPDIR/wheels
        rm -rf "$WHEELS" "$PACKAGES"
        mkdir -p "$WHEELS"
        info "Building packages from $req ..."
        #----
        cp ${BASH_SOURCE[0]} $TMPDIR/install.sh
        sort $req >$TMPDIR/requirements.txt
        if [ -e "$con" ]; then
            cp $con $TMPDIR/constraints.txt
        fi
        echo >&2 "Bundling via $* -r $TMPDIR/requirements.txt ${con:+-c ${TMPDIR}/constraints.txt}"
        do_bundle "$@" -r $TMPDIR/requirements.txt ${con:+-c ${TMPDIR}/constraints.txt}
        echo >&2 "Creating $output ..."
        rm -vf "${output}"
        if [[ $output =~ .zip$ ]]; then
            (cd $TMPDIR && zip -7r "${output}" install.sh requirements.txt ${con:+constraints.txt} wheels)
        else
            tar caf "$output" --owner=root --group=root -C "${TMPDIR}" install.sh requirements.txt ${con:+constraints.txt} wheels
        fi
    fi
}

main "$@"
exit
__PAYLOAD__STARTS__
