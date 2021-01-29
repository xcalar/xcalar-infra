#!/bin/bash

set -x
WRAPPED=$(readlink -f ${BASH_SOURCE[0]})
WRAPPED="${WRAPPED%.*}"

declare -A QP

query_string() {
    saveIFS=$IFS
    IFS='=&'
    local -a parm=($QUERY_STRING)
    IFS=$saveIFS
    for ((i=0; i<${#parm[@]}; i+=2)); do
        QP[${parm[i]}]=${parm[i+1]}
    done
}

query_string

SEP=${QP[sep]}
WORDS=${QA[words]}

OUTPUT=$($WRAPPED ${SEP+-separator $SEP} ${WORDS+-words $WORDS})

cat <<EOF
Content-type: text/plain

$OUTPUT
EOF
