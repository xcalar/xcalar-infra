#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

usage() {
    say "usage: $0 [-h|--help] -i <input file> -f <test JSON file>"
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
    LDAP_TYPE=$(jq -r .Build.LdapType $TEST_FILE)
    LDAP_DOMAIN=$(jq -r .Build.IntLdapDomain $TEST_FILE)
    LDAP_PASSWORD=$(jq -r .Build.IntLdapPassword $TEST_FILE)
    if [ -n "$TEST_CASE" ]; then
        CASE_LDAP_TYPE=$(jq -r .BuildCase.$TEST_CASE.LdapType $TEST_FILE)
        if [ "$CASE_LDAP_TYPE" != "null" ]; then
            LDAP_TYPE="$CASE_LDAP_TYPE"
        fi

        CASE_LDAP_DOMAIN=$(jq -r .BuildCase.$TEST_CASE.IntLdapDomain $TEST_FILE)
        if [ "$CASE_LDAP_DOMAIN" != "null" ]; then
            LDAP_DOMAIN="$CASE_LDAP_DOMAIN"
        fi

        CASE_LDAP_PASSWORD=$(jq -r .BuildCase.$TEST_CASE.IntLdapPassword $TEST_FILE)
        if [ "$CASE_LDAP_PASSWORD" != "null" ]; then
            LDAP_PASSWORD="$CASE_LDAP_PASSWORD"
        fi
    fi
}

parse_args "$@"

parse_test_file

task "Testing cluster"

EXT_LDAP_IP=$(echo $EXT_CLUSTER_IPS | cut -d ',' -f1)
ssh_ping $EXT_LDAP_IP

is_int_ext "LDAP_TYPE" "$LDAP_TYPE"

case "$LDAP_TYPE" in
    ext|EXT)
        exit 0
        ;;
esac

LDAP_DOMAIN=$(echo "$LDAP_DOMAIN" | sed -e 's/\./,dc=/g')
LDAP_DOMAIN="dc=${LDAP_DOMAIN}"
LDAP_ADMIN_DN="cn=admin,$LDAP_DOMAIN"

LDIF_FILE="$TMPDIR/ldap.$$.$RANDOM"
REMOTE_LDIF_FILE=$(basename "$LDIF_FILE")


cat >$LDIF_FILE <<EOF
dn: mail=jenkins@gmail.com,ou=People,$LDAP_DOMAIN
changetype: add
mail: jenkins@gmail.com
sn: User
cn: Jenkins
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
employeeType: administrator
userPassword: {SSHA}lW5BF/70xEhkPh3RjTKfhkElzygNQv2l

dn: mail=sPerson2@gmail.com,ou=People,$LDAP_DOMAIN
changetype: add
mail: sPerson2@gmail.com
sn: sp2_last
cn: sp2_first
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
employeeType: normal user
userPassword: {ssha}F1DuToFACcR3MypssVZyjTevXabvsAhI1BWkfA=

dn: mail=sPerson1@gmail.com,ou=People,$LDAP_DOMAIN
changetype: add
mail: sPerson1@gmail.com
sn: sp1_last
cn: sp1_first
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
employeeType: administrator
userPassword: {ssha}Fm3QtPRxd/qgUTDPQuKCj+nTMnRAyrl2+t3Vaw=

dn: mail=sPerson3@gmail.com,ou=People,$LDAP_DOMAIN
changetype: add
mail: sPerson3@gmail.com
sn: Smith
cn: Micheal
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
employeeType: administrator
userPassword: {ssha}Bt/n7NtErTBojSW8iSc8mlnLzYf6wlJx9RVE7g=

dn: mail=sPerson4@gmail.com,ou=People,$LDAP_DOMAIN
changetype: add
mail: sPerson4@gmail.com
sn: tttt
cn: kkkk
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
userPassword: {ssha}fnxVXrWpEMN/RQzTiBIFDguOFf/8axIa5e0Dsg=

dn: cn=xceUsers,ou=Groups,$LDAP_DOMAIN
changetype: modify
add: uniqueMember
uniqueMember: mail=jenkins@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson2@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson1@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson3@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson4@gmail.com,ou=People,$LDAP_DOMAIN

dn: cn=administrators,ou=Groups,$LDAP_DOMAIN
changetype: modify
add: uniqueMember
uniqueMember: mail=sPerson1@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson3@gmail.com,ou=People,$LDAP_DOMAIN
-
add: uniqueMember
uniqueMember: mail=sPerson4@gmail.com,ou=People,$LDAP_DOMAIN
EOF


task "Updating LDAP database"
scp_cmd "$LDIF_FILE" "${EXT_LDAP_IP}:" || die 1 "Unable to copy LDIF file to LDAP host $EXT_LDAP_IP" || die 1 "Error copying LDIF file"

ssh_cmd $EXT_LDAP_IP "ldapmodify -c -x -w $LDAP_PASSWORD -H ldapi:/// -D $LDAP_ADMIN_DN -f ./$REMOTE_LDIF_FILE" || die 1 "Error adding LDIF data"

task "Cleaning up after update"
ssh_cmd $EXT_LDAP_IP "rm -f $REMOTE_LDIF_FILE" || die 1 "Error removing remote LDIF file"

rm -f "$LDIF_FILE" || die 1 "Error removing LDIF file"

