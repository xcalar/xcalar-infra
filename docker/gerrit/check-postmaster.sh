#!/bin/bash
#
# Restart postfix in the gerrit container if it isn't running
#
CONTAINER_NAME="${1:-xcalarinfra_gerrit_1}"
if docker inspect "${CONTAINER_NAME}"; then
    if KPID=$(docker exec -u root "${CONTAINER_NAME}" cat /var/spool/postfix/pid/master.pid) && test -n "$KPID"; then
        if ! docker exec -u root "${CONTAINER_NAME}" /bin/kill -0 $KPID; then
            docker exec -u root "${CONTAINER_NAME}" /bin/service postfix restart
        fi
    fi
fi
exit $?
