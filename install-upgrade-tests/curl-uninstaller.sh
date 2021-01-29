#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

INSTALLER_PORT=8543

. $DIR/integration-sh-lib

SILENT=0

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help]  [-t <test name>] -i <input file> -f <test JSON file>"
    say "-t - name of test from the JSON file to execute"
    say "-i - input file describing the cluster"
    say "-f - JSON file describing the cluster and the tests to run"
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
            -t)
                TEST_CASE="$1"
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
            -d)
                DELETE="1"
                ;;
            -f)
                TEST_FILE="$1"
                shift

                if [ ! -e "$TEST_FILE" ]; then
                    say "Test config file $TEST_FILE does not exist"
                    exit 1
                fi
                ;;
            *)
                say "Unknown command $cmd"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$TEST_FILE" ]; then
        say "No test file specified"
        exit 1
    fi

    if [ -z "$INPUT_FILE" ]; then
        say "No input file specified"
        exit 1
    fi
}

parse_test_file() {
    task "Parsing test config file"

    t_start="$(date +%s)"
    TEST_NAME=$(jq -r ".TestName" $TEST_FILE)
    INSTALL_USERNAME=$(jq -r ".InstallUsername" $TEST_FILE)
    ACCESS_PUBKEY=$(jq -r ".AccessPublicKey" $TEST_FILE)
    eval ACCESS_PUBKEY=$ACCESS_PUBKEY
    ACCESS_PUBKEY=$(readlink -f "$ACCESS_PUBKEY")
    if [ -n $ACCESS_PUBKEY ]; then
        ACCESS_PRIVKEY=${ACCESS_PUBKEY%".pub"}
    fi
    LICENSE_FILE=$(jq -r ".LicenseFile" $TEST_FILE)
    eval LICENSE_FILE=$LICENSE_FILE
    LICENSE_FILE=$(readlink -f "$LICENSE_FILE")

    INSTALLER_PROTOCOL=$(jq -r ".InstallerFile.Protocol" $TEST_FILE)

    PARAMETER_LIST="INT_LDAP_PASSWORD:IntLdapPassword INT_LDAP_DOMAIN:IntLdapDomain INT_LDAP_ORG:IntLdapOrg EXT_LDAP_URI:ExtLdapUri EXT_LDAP_USERDN:ExtLdapUserDn EXT_LDAP_FILTER:ExtLdapFilter EXT_LDAP_CERT_FILE:ExtLdapCertFile EXT_LDAP_ACTIVEDIR:ExtLdapActiveDir EXT_LDAP_USETLS:ExtLdapUseTLS NFS_SERVER:NfsServer NFS_MOUNT:NfsMount NFS_USER:NfsUser NFS_GROUP:NfsGroup LDAP_TYPE:LdapType NFS_TYPE:NfsType INSTALLER_LOC:InstallerLoc INSTALL_DIR:InstallDir SERDES_DIR:SerDes"

    # for each of the VAR:TAG pairs in PARAMETER_LIST, create a variable named $VAR
    # and set it to the JSON value set by $TAG, unless a $TEST_CASE is set.  If it
    # is set, the variable $VAR is set to the JSON value of $TEST_CASE.$TAG
    for PARM in $PARAMETER_LIST; do
        VAR=$(echo "$PARM" | cut -d ":" -f1)
        TAG=$(echo "$PARM" | cut -d ":" -f2)

        eval $VAR=\"$(jq -r .Build.$TAG $TEST_FILE)\"

        if [ -n "$TEST_CASE" ]; then
            eval CASE_$VAR=\"$(jq -r .BuildCase.$TEST_CASE.$TAG $TEST_FILE)\"
            VAR_NAME=CASE_$VAR

            if [ ${!VAR_NAME} != "null" ]; then
                declare $VAR="${!VAR_NAME}"
            fi
        fi

        echo "$VAR = ${!VAR}"
    done

    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

parse_discovery_result () {
    XML_RESULT=$(echo "$RETVAL" | jq -r .discoverResult)
    RC=$?

    if [ "$RC" != "0" ]; then
        echo "Error parsing discovery result"
        return 1
    fi

    XCE_ROOT_PATH=$(echo "$XML_RESULT" | jq -r .xcalarRoot)

    EXT_CLUSTER_IPS=""
    for HOST in $(echo "$XML_RESULT" | jq -r .hosts[]); do
       if [ -z "$EXT_CLUSTER_IPS" ]; then
           EXT_CLUSTER_IPS="$HOST"
       else
           EXT_CLUSTER_IPS="${EXT_CLUSTER_IPS},${HOST}"
       fi
    done

    INT_CLUSTER_IPS=""
    for HOST in $(echo "$XML_RESULT" | jq -r .privHosts[]); do
       if [ -z "$INT_CLUSTER_IPS" ]; then
           INT_CLUSTER_IPS="$HOST"
       else
           INT_CLUSTER_IPS="${INT_CLUSTER_IPS},${HOST}"
       fi
    done
}

prepare_tokens () {
    local -a NFS_ARGS=()
    local -a LDAP_ARGS=()

    UNINSTALL_TOKEN=$($DIR/install-json-wrapper2.py --installDir "$INSTALL_DIR" "${INSTALLER_LOC_ARGS[@]}" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY")
}

parse_args "$@"

parse_test_file

task "Testing cluster"

ssh_ping $EXT_INSTALL_IP || die 1 "Cannot contact install host $EXT_TEST_IP"
pssh_ping $EXT_CLUSTER_IPS || die 1 "Cannot contact one or more of cluster hosts $EXT_CLUSTER_IPS"
NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)

task "Building configuration"

is_true_false "EXT_LDAP_ACTIVEDIR" "$EXT_LDAP_ACTIVEDIR"
is_true_false "EXT_LDAP_USETLS" "$EXT_LDAP_USETLS"

is_int_ext "LDAP_TYPE" "$LDAP_TYPE"
is_int_ext "NFS_TYPE" "$NFS_TYPE"

is_int_ext "INSTALLER_LOC" "$INSTALLER_LOC"

case $INSTALLER_PROTOCOL in
    1.3.0)
        ;;
    *)
        echo "[0] [FAILURE] Unknown installer protocol \"$INSTALLER_PROTOCOL\""
        exit 1
        ;;
esac

DISCOVER_CMD="xdp/discover"
UNINSTALL_CMD="xdp/uninstallation/start"
STATUS_CMD="xdp/uninstallation/status"

echo "#license_json $LICENSE_TOKEN"

DISCOVERY_HOST=$(echo "$INT_CLUSTER_IPS" | cut -d ',' -f1)

DISCOVERY_TOKEN=$($DIR/install-json-wrapper2.py --installDir "$INSTALL_DIR" -n "$DISCOVERY_HOST" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY")

task "Starting Xcalar discovery"
run_installer_post_cmd "$DISCOVERY_TOKEN" "$EXT_INSTALL_IP" "$DISCOVER_CMD" || die 1 "[0] [FAILURE] discovery error: $RETVAL"

echo "DISCOVERY TOKEN: $RETVAL"

parse_discovery_result || die 1 "[0] [FAILURE] discovery parse error"

case "$INSTALLER_LOC" in
    ext|EXT)
        INSTALLER_LOC_ARGS=(-n "$EXT_CLUSTER_IPS" -p "$INT_CLUSTER_IPS")
        ;;
    int|INT)
        INSTALLER_LOC_ARGS=(-n "$INT_CLUSTER_IPS")
        ;;
esac

prepare_tokens

echo "#uninstall_json $UNINSTALL_TOKEN"

task "Starting Xcalar uninstall"
run_installer_post_cmd "$UNINSTALL_TOKEN" "$EXT_INSTALL_IP" "$UNINSTALL_CMD" || die 1 "[0] [FAILURE] install start error: $RETVAL"
echo

log_fname="/tmp/$TEST_NAME-$TEST_ID-gui-uninstall.log"
arch_log_fname="${TMPDIR}/$TEST_NAME-$TEST_ID-gui-uninstall.$$.${RANDOM}.log"
hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
my_username=$(id -un)
install_log_fname="/tmp/$my_username/uninstall-installer.log"

check_status_1_1_0 "$UNINSTALL_TOKEN"

if [ -n "$DELETE" ]; then
    task "Deleting the contents of XcalarRoot"
    ssh_cmd "$NODE_ZERO" "sudo rm -rf $XCE_ROOT_PATH/*" || die 1 "[0] [FAILURE] Unable to delete contents of $XCE_ROOT_PATH"
    echo "[0] [SUCCESS] XcalarRoot deleted"
fi

echo "[0] [SUCCESS] Xcalar uninstall completed."
echo
