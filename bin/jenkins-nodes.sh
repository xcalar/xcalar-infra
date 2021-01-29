#!/bin/bash

XLRINFRADIR="${XLRINFRADIR:-$(cd "$(dirname ${BASH_SOURCE[0]})/.." && pwd)}"
NODE_STATUS="${1:-NODE_ONLINE}"
"${XLRINFRADIR}/bin/jenkins-cli.sh" groovysh <  "${XLRINFRADIR}/jenkins/groovy/list_nodes.groovy" | grep $NODE_STATUS | sed -e 's/^'${NODE_STATUS}'=//g'
