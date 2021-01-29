#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] -i <input file> -u <username> -p <password>"
    say "-u - username"
    say "-p - password"
    say "-i - input file describing the cluster"
    say "-h|--help - this help message"
}

parse_args() {

    if [ -z "$1" ]; then
        usage
        exit 1
    fi

    while test $# -gt 0; do
        cmd="$1"
        shift
        case $cmd in
            --help|-h)
                usage
                exit 1
                ;;
            -u)
                USER_NAME="$1"
                shift
                ;;
            -p)
                USER_PASS="$1"
                shift
                ;;
            -i)
                INPUT_FILE="$1"
                shift

                if [ ! -e "$INPUT_FILE" ]; then
                    say "Input config file $INPUT_FILE does not exist"
                    exit 1
                fi
                . $INPUT_FILE
                ;;
            *)
                say "Unknown command $cmd"
                usage
                exit 1
                ;;
        esac
    done

    [ -z "$INPUT_FILE" ] && die 1 "[0] [FAILURE] No input file specified"
    [ -z "$USER_NAME" ] && die 1 "[0] [FAILURE] No username specified"
    [ -z "$USER_PASS" ] && die 1 "[0] [FAILURE] No password specified"
}

#
# $1 - host/ip
# $2 - username
# $3 - password
#
run_login_cmd() {
    LOGIN_JSON="{\"xipassword\":\"$3\",\"xiusername\":\"$2\"}"

    RETVAL=$(curl -k -s -X POST -H "Content-Type: application/json" --data "$LOGIN_JSON" https://${1}:8443/app/login 2>&1)
    rc=$?

    return $rc
}

parse_args "$@"

task "Testing cluster"
NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
ssh_ping $NODE_ZERO

task "Attempting log in to $NODE_ZERO as $USER_NAME/$USER_PASS"
run_login_cmd "$NODE_ZERO" "$USER_NAME" "$USER_PASS" || die 1 "[0] [FAILURE] Unable to contact cluster"

LOGIN_STATUS=$(echo "$RETVAL" | jq -r .status)

case "$LOGIN_STATUS" in
    200)
        LOGIN_VALID="$(echo "$RETVAL" | jq -r .isValid)"
        if [ "$LOGIN_VALID" == "true" ]; then
            echo "[0] [SUCCESS] Login successful"
            exit 0
        else
            echo "[0] [FAILURE] Login failed"
            exit 1
        fi
        ;;
    *)
        echo "[0] [FAILURE] Unknown response: $RETVAL"
        exit 1
        ;;
esac
