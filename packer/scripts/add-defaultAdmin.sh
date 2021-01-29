#!/bin/bash

# Fix local admin login
if test -e /etc/default/xcalar; then
    . /etc/default/xcalar
fi

XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
XCE_HOME=${XCE_HOME:-$(awk -F'=' '/^Constants.XcalarRootCompletePath/{print $2}' $XCE_CONFIG)}
CONF=${XCE_HOME:-/var/opt/xcalar}/config

mkdir -p $CONF
cat > $CONF/defaultAdmin.json <<'EOF'
{
  "username": "xdpadmin",
  "password": "9021834842451507407c09c7167b1b8b1c76f0608429816478beaf8be17a292b",
  "email": "info@xcalar.com",
  "defaultAdminEnabled": true
}
EOF
chmod 0700 $CONF
chmod 0600 $CONF/defaultAdmin.json
chown -R xcalar:xcalar $CONF

exit 0
