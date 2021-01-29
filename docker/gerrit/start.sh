#!/bin/bash

git config -f $GERRIT_HOME/gerrit/etc/gerrit.config auth.type $AUTH_TYPE
$GERRIT_HOME/gerrit/bin/gerrit.sh start
if [ $? -eq 0 ]
then
    PIDFILE=$GERRIT_HOME/gerrit/logs/gerrit.pid
#    until test -f $PIDFILE; do
#        sleep 2
#    done
#    GPID=$(cat $PIDFILE)
    echo "gerrit $GERRIT_VERSION is started successfully with auth.type=$AUTH_TYPE, please login to check."
    echo ""
    exec tail -f $GERRIT_HOME/gerrit/logs/*_log
else
    cat $GERRIT_HOME/gerrit/logs/error_log
    exit 1
fi
