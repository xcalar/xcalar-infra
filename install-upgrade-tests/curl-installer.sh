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

prepare_tokens_1 () {
    local OPT_ARGS=""

    [ -n "$INSTALL_DIR" ] && OPT_ARGS="--installDir $INSTALL_DIR"

    case "$NFS_TYPE" in
        ext|EXT)
            INSTALL_TOKEN=$($DIR/install-json-wrapper.py "${INSTALLER_LOC_ARGS[@]}" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY" --nfsServer "$NFS_SERVER" --nfsMntPt "$NFS_MOUNT/$TEST_NAME-$TEST_ID" $OPT_ARGS)
            ;;
        int|INT)
            INSTALL_TOKEN=$($DIR/install-json-wrapper.py "${INSTALLER_LOC_ARGS[@]}" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY" $OPT_ARGS)
            ;;
        reuse|REUSE)
            INSTALL_TOKEN=$($DIR/install-json-wrapper.py "${INSTALLER_LOC_ARGS[@]}" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY" --nfsReuse "/mnt/xcalar" $OPT_ARGS)
    esac

    case "$LDAP_TYPE" in
        ext|EXT)
            LDAP_TOKEN=$($DIR/ext-ldap-json-wrapper.py -l "$EXT_LDAP_URI" -u "$EXT_LDAP_USERDN" -s "$EXT_LDAP_FILTER" -k "$EXT_LDAP_CERT_FILE" -a "$EXT_LDAP_ACTIVEDIR" -t "$EXT_LDAP_USETLS")
            ;;
        int|INT)
            LDAP_TOKEN=$($DIR/int-ldap-json-wrapper.py -p "$INT_LDAP_PASSWORD" -d "$INT_LDAP_DOMAIN" -c "$INT_LDAP_ORG")
            ;;
    esac
}

prepare_tokens_2 () {
    local -a NFS_ARGS=()
    local -a LDAP_ARGS=()

    case "$NFS_TYPE" in
        ext|EXT)
            NFS_ARGS=(--nfsServer "$NFS_SERVER" --nfsMntPt "$NFS_MOUNT/$TEST_NAME-$TEST_ID" --nfsOption "$NFS_TYPE")
            ;;
        int|INT)
            NFS_ARGS=(--nfsOption "$NFS_TYPE")
            ;;
    esac

    case $LDAP_TYPE in
        ext|EXT)
            LDAP_ARGS=(--ldapURI "$EXT_LDAP_URI" --ldapUserDN "$EXT_LDAP_USERDN" --ldapSearchFilter "$EXT_LDAP_FILTER" --ldapKeyFile "$EXT_LDAP_CERT_FILE" --ldapActiveDir "$EXT_LDAP_ACTIVEDIR" --ldapUseTLS "$EXT_LDAP_USETLS" --ldapInstall='false')
            ;;
        int|INT)
            LDAP_ARGS=(--ldapDomain "$INT_LDAP_DOMAIN" --ldapPassword "$INT_LDAP_PASSWORD" --ldapCompanyName "$INT_LDAP_ORG" --ldapInstall='true')
            ;;
    esac

    INSTALL_TOKEN=$($DIR/install-json-wrapper2.py --preConfig --serDesDir "$SERDES_DIR" --installDir "$INSTALL_DIR" "${INSTALLER_LOC_ARGS[@]}" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY" "${NFS_ARGS[@]}" "${LDAP_ARGS[@]}")
}

parse_args "$@"

parse_test_file

task "Testing cluster"

ssh_ping $EXT_INSTALL_IP || die 1 "Cannot contact install host $EXT_TEST_IP"
pssh_ping $EXT_CLUSTER_IPS || die 1 "Cannot contact one or more of cluster hosts $EXT_CLUSTER_IPS"

task "Building configuration"

is_true_false "EXT_LDAP_ACTIVEDIR" "$EXT_LDAP_ACTIVEDIR"
is_true_false "EXT_LDAP_USETLS" "$EXT_LDAP_USETLS"

is_int_ext "LDAP_TYPE" "$LDAP_TYPE"
is_int_ext "NFS_TYPE" "$NFS_TYPE"

is_int_ext "INSTALLER_LOC" "$INSTALLER_LOC"

LICENSE_TOKEN=$($DIR/license-json-wrapper.py -l "$LICENSE_FILE")

case $INSTALLER_PROTOCOL in
    1.3.0|1.2.1|1.2.0|1.1.0|1.0.0)
        ;;
    *)
        echo "[0] [FAILURE] Unknown installer protocol \"$INSTALLER_PROTOCOL\""
        exit 1
        ;;
esac

case $INSTALLER_PROTOCOL in
    1.3.0|1.2.1|1.2.0)
        INSTALLER_PORT=8543
        ;;
    *)
        INSTALLER_PORT=8443
        ;;
esac

case "$INSTALLER_LOC" in
    ext|EXT)
        INSTALLER_LOC_ARGS=(-n "$EXT_CLUSTER_IPS" -p "$INT_CLUSTER_IPS")
        ;;
    int|INT)
        INSTALLER_LOC_ARGS=(-n "$INT_CLUSTER_IPS")
        ;;
esac

echo "$NFS_TYPE"
case $INSTALLER_PROTOCOL in
    1.3.0)
        prepare_tokens_2
        ;;
    *)
        prepare_tokens_1
        ;;
esac

case $INSTALLER_PROTOCOL in
    1.0.0)
        LICENSE_CMD="checkLicense"
        INSTALL_CMD="runInstaller"
        STATUS_CMD="checkStatus"
        INT_LDAP_CMD="installLdap"
        EXT_LDAP_CMD="writeConfig"
        ;;
    1.2.0|1.1.0)
        LICENSE_CMD="xdp/license/verification?licenseKey=$(cat $LICENSE_FILE)"
        INSTALL_CMD="xdp/installation/start"
        STATUS_TOKEN=$($DIR/url-encode-wrapper.py -n "$EXT_CLUSTER_IPS" -u "$INSTALL_USERNAME" -f "$ACCESS_PRIVKEY")
        STATUS_CMD="xdp/installation/status?${STATUS_TOKEN}"
        INT_LDAP_CMD="ldap/installation"
        EXT_LDAP_CMD="ldap/config"
        ;;
    1.2.1)
        LICENSE_CMD="xdp/license/verification"
        INSTALL_CMD="xdp/installation/start"
        STATUS_CMD="xdp/installation/status"
        INT_LDAP_CMD="ldap/installation"
        EXT_LDAP_CMD="ldap/config"
        ;;
    1.3.0)
        LICENSE_CMD="xdp/license/verification"
        INSTALL_CMD="xdp/installation/start"
        STATUS_CMD="xdp/installation/status"
        ;;
esac

echo "#license_json $LICENSE_TOKEN"
echo "#install_json $INSTALL_TOKEN"
echo "#ldap_json $LDAP_TOKEN"

task "Sending license"
case $INSTALLER_PROTOCOL in
    1.3.0|1.2.1|1.0.0)
        run_installer_post_cmd "$LICENSE_TOKEN" "$EXT_INSTALL_IP" "$LICENSE_CMD" || die 1 "[0] [FAILURE] license error: $RETVAL"
        ;;
    1.2.0|1.1.0)
        run_installer_get_cmd "$EXT_INSTALL_IP" "$LICENSE_CMD" || die 1 "[0] [FAILURE] license error: $RETVAL"
        ;;
esac
echo "[0] [SUCCESS] License sent"
echo

task "Starting Xcalar install"
run_installer_post_cmd "$INSTALL_TOKEN" "$EXT_INSTALL_IP" "$INSTALL_CMD" || die 1 "[0] [FAILURE] install start error: $RETVAL"
echo

log_fname="/tmp/$TEST_NAME-$TEST_ID-gui-install.log"
arch_log_fname="${TMPDIR}/$TEST_NAME-$TEST_ID-gui-install.$$.${RANDOM}.log"
hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
my_username=$(id -un)
install_log_fname="/tmp/$my_username/installer.log"

case $INSTALLER_PROTOCOL in
    1.0.0)
        check_status_1_0_0
        ;;
    1.3.0|1.2.1|1.2.0|1.1.0)
        check_status_1_1_0 "$INSTALL_TOKEN"
        ;;
esac
echo "[0] [SUCCESS] Xcalar install completed."
echo

case $INSTALLER_PROTOCOL in
    1.2.1|1.2.0|1.1.0|1.0.0)
        task "Configuring ldap"
        case "$LDAP_TYPE" in
            ext|EXT)
                run_installer_put_cmd "$LDAP_TOKEN" "$EXT_INSTALL_IP" "$EXT_LDAP_CMD" || die 1 "[0] [FAILURE] external LDAP error: $RETVAL"
                ;;
            int|INT)
                run_installer_post_cmd "$LDAP_TOKEN" "$EXT_INSTALL_IP" "$INT_LDAP_CMD" || die 1 "[0] [FAILURE] internal LDAP error: $RETVAL"
                ;;
        esac
        echo "[0] [SUCCESS] ldap configuration completed."
        ;;
esac

echo "[0] [SUCCESS] Installation complete"
