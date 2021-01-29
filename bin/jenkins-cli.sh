#!/bin/bash

JENKINS_URL="${JENKINS_URL:-https://jenkins.int.xcalar.com/}"
JENKINS_URL="${JENKINS_URL%/}"

if [ -z "$JENKINS_HOST" ]; then
    JENKINS_HOST="${JENKINS_URL#https://}"
    JENKINS_HOST="${JENKINS_HOST#http://}"
    JENKINS_HOST="${JENKINS_HOST%/}"
    JENKINS_HOST="${JENKINS_HOST%:[0-9]*}"
fi

SSH_PORT="${SSH_PORT:-22022}"
SSH_USER="${USER}"

jenkins_cli () {
    ssh -oPort=${SSH_PORT} -oUser=${SSH_USER} ${JENKINS_HOST} "$@"
}

cmd_list_nodes() {
    curl -fsSL "${JENKINS_URL}/computer/api/json"
}

filter () { cat; }

usage () {
    cat << EOF
usage: $0 [-l list-plugins (list current plugins)] [-c command] [-n list-plugins (list newest plugins after restart)] [-p port] [-u username] -- [jenkins-cli args]

    -l list-plugins   : output currently loaded plugins in plugin:version format
    -n list-plugins   : output updated plugins in plugin:version format
    -c list-nodes     : list all nodes as json. use jq for extra processing
    -u <username>     : use given username instead of $SSH_USER
    -p <port>         : use given port instead of $SSH_PORT
    -H <hostname>     : connect to this host instead of the default derived from JENKINS_URL ($JENKINS_HOST)

    Usage samples

    Show all offline slaves:
      jenkins-cli.sh -c list-nodes | jq -r '[.computer[]|select(.offline == true)|.displayName]'

    --

EOF
    exit 1
}

test $# -gt 0 || set -- help


while getopts "hlnc:u:p:H:" opt "$@"; do
    case $opt in
        h) usage;;
        H) JENKINS_HOST="$OPTARG";;
        u) SSH_USER="$OPTARG";;
        p) SSH_PORT="$OPTARG";;
        l) filter() { tr -d '()' | awk '{printf "%s:%s\n",$1,$(NF)}'; };;
        n) filter() { sed -re 's/\([0-9].*//g' | awk '{printf "%s:%s\n",$1,$(NF)}'; };;
        c) eval cmd_${OPTARG//-/_}; exit;;
        -*) break;;
        --) break;;
    esac
done
shift $((OPTIND-1))
jenkins_cli "$@" | filter
exit ${PIPESTATUS[0]}
