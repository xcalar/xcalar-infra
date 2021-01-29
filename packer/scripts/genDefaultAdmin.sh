#!/bin/bash
set -e

export PATH=/opt/xcalar/bin:$PATH

gen_password() {
    node -e 'var crypto=require("crypto"); var hmac=crypto.createHmac("sha256", "xcalar-salt").update("'$1'").digest("hex"); process.stdout.write(hmac+"\n")'
}

test_gen_password() {
    test "$(gen_password admin)" = "6d51d4b15ded3bc357f6f1547de49cc81579e6a3b1ec85bbf50dcca20618d1c4"
}

usage() {
    echo "usage: $0 [-u|--username username] [-e|--email email] [-p|--password password]"
    echo " generates a json for use with XCE_HOME/config/defaultAdmin.json (must be mode 0600!)"
    exit 1
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -u|--username) ADMIN_USERNAME="$1"; shift;;
        -p|--password) ADMIN_PASSWORD="$1"; shift;;
        -e|--email) ADMIN_EMAIL="$1"; shift;;
        -h|--help) usage;;
        *) echo >&2 "ERROR: Unknown argument $cmd"; usage;;
    esac
done

test_gen_password

: ${ADMIN_USERNAME:?Must specify --username}
: ${ADMIN_EMAIL:?Must specify --email}
: ${ADMIN_PASSWORD:?Must specify --password}

cat <<EOF
{
  "username": "$ADMIN_USERNAME",
  "password": "$(gen_password $ADMIN_PASSWORD)",
  "email": "$ADMIN_EMAIL",
  "defaultAdminEnabled": true
}
EOF
