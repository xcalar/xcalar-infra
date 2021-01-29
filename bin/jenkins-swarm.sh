#!/bin/bash

if [ -z "$SWARM_JAR" ]; then
    SWARM_URL="${SWARM_URL:-http://repo.xcalar.net/deps/swarm-client-3.15.jar}"
    SWARM_JAR="$(mktemp -t $(basename "$SWARM_URL" .jar)-XXXXXX.jar)"
    curl -o "$SWARM_JAR" "$SWARM_URL"
fi

cvault() {
    curl -fsSL -H "Authorization: Bearer $SWARM_VAULT_TOKEN" "$@"
}

# Generate a new token: vault token create -orphan -display-name=swarm-token -policy=swarm
export VAULT_ADDR=${VAULT_ADDR:-https://vault.service.consul:8200}
SWARM_VAULT_KEY="${SWARM_VAULT_KEY:-secret/data/roles/jenkins-slave/swarm}"
SWARM_VAULT_TOKEN="${SWARM_VAULT_TOKEN:-s.HlpsyJi6SE8ME6KyqpRO9HC2}"

SWARM_USERPASS=($(cvault "${VAULT_ADDR}/v1/${SWARM_VAULT_KEY}" | jq -r '.data.data|.username,.password'))

SWARM_USER="${SWARM_USERPASS[0]}"
export SWARM_PASS="${SWARM_USERPASS[1]}"
if [ -z "$SWARM_PASS" ]; then
    echo >&2 "ERROR: Unable to fetch credentials for swarm user"
    exit 1
fi

SWARM_USER=swarm
SWARM_MASTER="${SWARM_MASTER:-https://jenkins.int.xcalar.com}"
SWARM_FSROOT=${SWARM_FSROOT:-$(pwd)}
SWARM_NAME="${SWARM_NAME:-$(hostname -f)}"
SSL_FINGERPRINTS="${SSL_FINGERPRINTS-D7:F9:76:25:B2:7D:E9:00:59:00:9B:CD:CE:6B:5F:97:9E:2F:68:A3:79:13:FE:F6:43:9F:A7:D0:5B:AC:7F:78}"

JAVA_HOME=$(readlink -f $(command -v java))
export JAVA_HOME="${JAVA_HOME%/bin/java}"

exec java $JAVA_OPTIONS -jar "$SWARM_JAR" -fsroot "$SWARM_FSROOT" ${SSL_FINGERPRINTS+-sslFingerprints $SSL_FINGERPRINTS} -deleteExistingClients -name "$SWARM_NAME" -mode exclusive -pidFile $SWARM_FSROOT/swarm.pid -master $SWARM_MASTER -username $SWARM_USER -passwordEnvVariable SWARM_PASS "$@"
