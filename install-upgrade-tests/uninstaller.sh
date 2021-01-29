#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help|-p] -i <input file> -f <test JSON file>"
    say "-p - preserve installation defaults"
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
            -p)
                PRESERVE_DEFAULTS=1
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
    OS_VERSION=$(jq -r .TestClusterConfig.OSVersion $TEST_FILE)
    LDAP_TYPE=$(jq -r .Build.LdapType $TEST_FILE)
    NFS_TYPE=$(jq -r .Build.NfsType $TEST_FILE)
    if [ -n "$TEST_CASE" ]; then
        CASE_LDAP_TYPE=$(jq -r .BuildCase.$TEST_CASE.LdapType $TEST_FILE)
        if [ "$CASE_LDAP_TYPE" != "null" ]; then
            LDAP_TYPE="$CASE_LDAP_TYPE"
        fi

        CASE_NFS_TYPE=$(jq -r .BuildCase.$TEST_CASE.NfsType $TEST_FILE)
        if [ "$CASE_NFS_TYPE" != "null" ]; then
            NFS_TYPE="$CASE_NFS_TYPE"
        fi
    fi
}

remove_xcalar() {
    hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
    rc=0
    pssh_cmd "sudo yum -y remove xcalar xcalar-python36 xcalar-node" || die 1 "Could not remove Xcalar rpms from one or more cluster hosts $EXT_CLUSTER_IPS"
    rc=$(( $rc + $? ))
    # this deals with cases where our dependency package names have changed
    # when downgrading to an older version
    pssh_cmd "sudo yum -y remove nodejs-*"
    rc=$(( $rc + $? ))
    pssh_cmd "sudo rm -rf /opt/xcalar/* /etc/xcalar /etc/default/xcalar /var/log/xcalar /var/log/Xcalar* /var/opt/xcalar"
    rc=$(( $rc + $? ))
    if [ -n "$PRESERVE_DEFAULTS" ]; then
        pssh_cmd "[ test -f /etc/default/xcalar.rpmsave ] && sudo mv /etc/default/xcalar.rpmsave /etc/default/xcalar"
        rc=$(( $rc + $? ))
        pssh_cmd "sudo echo \"#XCE_UID=5023\" >> /etc/default/xcalar"
    fi

    return $rc
}

remove_nfs() {
    hosts_array=($(echo $EXT_CLUSTER_IPS | sed -e 's/,/\n/g'))
    NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
    rc=0

    task "Restarting NFS server"
    case "$OS_VERSION" in
        RHEL6|rhel6|CENTOS6|centos6)
            ssh_cmd "$NODE_ZERO" "sudo service nfs condrestart"
            rc=$(( $rc + $? ))
            ;;
        RHEL7|rhel7|CENTOS7|centos7)
            ssh_cmd "$NODE_ZERO" "sudo service nfs-server try-restart"
            rc=$(( $rc + $? ))
            ;;
    esac

    return $rc
}

remove_ldap() {
    NODE_ZERO=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
    rc=0

    task "Removing LDAP server"
    ssh_cmd "$NODE_ZERO" "sudo service slapd stop"
    rc=$(( $rc + $? ))
    ssh_cmd "$NODE_ZERO" "sudo rm -rf /etc/rsyslog.d/91-slapd.conf"
    rc=$(( $rc + $? ))

    case "$OS_VERSION" in
        RHEL6|rhel6|CENTOS6|centos6)
            ssh_cmd "$NODE_ZERO" "sudo service rsyslog condrestart"
            rc=$(( $rc + $? ))
            ;;
        RHEL7|rhel7|CENTOS7|centos7)
            ssh_cmd "$NODE_ZERO" "sudo service rsyslog try-restart"
            rc=$(( $rc + $? ))
            ;;
    esac

    ssh_cmd "$NODE_ZERO" "sudo yum -y remove openldap-clients openldap-servers"
    rc=$(( $rc + $? ))

    ssh_cmd "$NODE_ZERO" "sudo rm -rf /var/log/slapd /var/lib/ldap /etc/openldap /opt/ca"
    rc=$(( $rc + $? ))

    return $rc
}

parse_args "$@"

parse_test_file

task "Testing Cluster"
pssh_ping $EXT_CLUSTER_IPS || die 1 "Cannot contact one or more of cluster hosts $EXT_CLUSTER_IPS"

is_int_ext "LDAP_TYPE" "$LDAP_TYPE"
is_int_ext "NFS_TYPE" "$NFS_TYPE"
is_os_type "OS_VERSION" "$OS_VERSION"

task_rc=0
task "Removing Xcalar software"
remove_xcalar
task_rc=$(( $task_rc + $?))

case "$NFS_TYPE" in
    int|INT)
        task "Removing NFS server"
        remove_nfs
        task_rc=$(( $task_rc + $?))
        ;;
esac

case "$LDAP_TYPE" in
    int|INT)
        task "Removing LDAP service"
        remove_ldap
        task_rc=$(( $task_rc + $?))
        ;;
esac

case "$OS_VERSION" in
    RHEL6|rhel6|CENTOS6|centos6)
        task "Uninstalling incompatible dependencies"
        pssh_cmd "sudo rpm -e --nodeps python27-zope-interface python27-datetime || true"
        ;;
esac

if [ $task_rc -ne 0 ]; then
    die 1 "[0] [FAILURE] One or more errors occurred during Xcalar uninstall"
fi

echo "[0] [SUCCESS] Xcalar successfully removed"
