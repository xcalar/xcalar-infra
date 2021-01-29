#!/bin/bash

if ((XTRACE)) || [[ $- == *x* ]]; then
    set -x
    export PS4='# [${PWD}] ${BASH_SOURCE#$PWD/}:${LINENO}: ${FUNCNAME[0]}() - ${container:+[$container] }[${SHLVL},${BASH_SUBSHELL},$?] '
fi

# Common set up
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XLRINFRADIR="$(cd "$DIR/.." && pwd)"
export PATH=$XLRINFRADIR/bin:$PATH:/opt/xcalar/bin

export PYCURL_SSL_LIBRARY=openssl
export LDFLAGS=-L/usr/local/opt/openssl/lib
export CPPFLAGS=-I/usr/local/opt/openssl/include

cd $XLRINFRADIR || exit 1

#rm -rf .venv
source $XLRINFRADIR/bin/infra-sh-lib
source $XLRINFRADIR/azure/azure-sh-lib
source $XLRINFRADIR/aws/aws-sh-lib

if [ -z "$XLRDIR" ] && [ -e doc/env/xc_aliases ]; then
    export XLRDIR=$PWD
fi

if [ -n "$XLRDIR" ]; then
    . doc/env/xc_aliases

    if type -t xcEnvEnterDir >/dev/null; then
        if ! xcEnvEnterDir "$XLRDIR/xcve"; then
            exit 1
        fi
    else
        if ! xcEnvEnter; then
            exit 1
        fi
    fi
    setup_proxy
elif test -e bin/activate; then
    source bin/activate
else
    make
    source .venv/bin/activate
fi

# First look in local (Xcalar) repo for a script and fall back to the one in xcalar-infra
for SCRIPT in "${XLRINFRADIR}"/jenkins/"${JOB_NAME}".sh; do
    if test -x "$SCRIPT"; then
        break
    fi
done

if ! test -x "${SCRIPT}"; then
    echo >&2 "No jenkins script for for $JOB_NAME"
    exit 1
fi

"$SCRIPT" "$@"
ret=$?

exit $ret
