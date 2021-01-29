#!/bin/bash

set -e

# test version: http://freenas2.int.xcalar.com:8080/netstore/infra/ldap/ldapConfig.json
# sso version: http://freenas2.int.xcalar.com:8080/netstore/infra/ldap/sso_login/ldapConfig.json
: "${LDAP_CONFIG_URL:?Need to set non-empty LDAP_CONFIG_URL}"

# set up admin account
echo 'This script will set up admin acct' >&2
ADMIN_USERNAME=${ADMIN_USERNAME:-xdpadmin}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-Welcome1}
ADMIN_EMAIL=${ADMIN_EMAIL:-support@xcalar.com}

XCE_CONFIG="${XCE_CONFIG:-/etc/xcalar/default.cfg}"
if [ ! -e "$XCE_CONFIG" ]; then
    echo "$XCE_CONFIG does not exist on $HOSTNAME!" >&2
    exit 1
fi

# get value of Constants.XcalarRootCompletePath from the default file,
# which should be path to xcalar home (shared storage if cluster)
# the Xcalar API we call to set up admin account will write in to this dir
XCE_HOME=$(awk -F'=' '/^Constants.XcalarRootCompletePath/{print $2}' $XCE_CONFIG) # could be /mnt/xcalar etc

# check if this value is empty... if so fail out because api call is not going to work
if [ -z "$XCE_HOME" ]; then
    echo "var Constants.XcalarRootCompletePath in $XCE_CONFIG is empty; Can't set up admin account on $HOSTNAME" >&2
    exit 1
fi

#XCE_HOME=/var/opt/xcalar
# ovirttool should have copied static defaultadmin.json file to VM's root
mkdir -p -m 0777 "$XCE_HOME/config"
mv /defaultAdmin.json "$XCE_HOME/config"
chown xcalar:xcalar "$XCE_HOME/config/defaultAdmin.json"
chmod 0600 "$XCE_HOME/config/defaultAdmin.json"
curl -sSL "$LDAP_CONFIG_URL" > "$XCE_HOME/config/ldapConfig.json"
chown xcalar:xcalar "$XCE_HOME/config/ldapConfig.json"
chmod 0600 "$XCE_HOME/config/ldapConfig.json"

