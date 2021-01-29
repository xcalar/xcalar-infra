#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_UPDATE=false
BUCKET=priv-xcbilling
GEN_HTML=false

update () {
    aws s3 sync s3://${BUCKET}/ ./billing/ || true
}

usage () {
    cat <<EOF >&2
    usage: $0 [-u|--update] [-t output html] [-b|--bucket BUCKET (default: $BUCKET)] -- list of csv files
EOF
    test $# -eq 0 || echo >&2 "$1"
    exit 1
}

get_total() {
    awk -F',' '/Total statement/{print $26}' | tr -d '"'
}


if [ "$(ls billing/*.csv | wc -l)" -eq 0 ]; then
    DO_UPDATE=true
fi
while getopts "htb:u" cmd; do
    case "$1" in
        -h|--help) usage;;
        -b|--bucket) BUCKET="$OPTARG";;
        -u|--update) DO_UPDATE=true;;
        -t|--table) GEN_HTML=true;;
        --) break;;
        -*) usage "ERROR: Unknown option $opt";;
    esac
done
shift $((OPTIND-1))

if $DO_UPDATE; then
    update
fi

test $# -gt 0 || set -- $(ls ./billing/*-aws-*.csv)

if $GEN_HTML; then
    printf '<html>\n'
    printf '<table border="1">\n'
    printf ' <tr>\n'
    printf '  <th> Statement </th>\n'
    printf '  <th> Total </th>\n'
    printf ' </tr>\n'
    for CSV in "$@"; do
        BN=$(basename $CSV)
        printf ' <tr>\n'
        printf '  <td><a href="%s">%s</td>\n' $BN $BN
        printf '  <td>%5.2f</td>\n' $(get_total < $CSV)
        printf ' </tr>\n'
    done
    printf '</table>\n'
    printf '</html>\n'
else
    for CSV in "$@"; do
        BN=$(basename $CSV)
        echo "$BN $(get_total < $CSV)"
    done
fi


