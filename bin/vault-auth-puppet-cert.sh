#!/bin/bash
#
# shellcheck disable=SC2086,SC2154

set +e
set +x

vault_lookup_self() {
    curl -fsSL -H "X-Vault-Request: true" -H "X-Vault-Token: $VAULT_TOKEN" "${VAULT_ADDR}/v1/auth/token/lookup-self?token=${1:-$VAULT_TOKEN}"
}

vault_renew() {
    sudo -H VAULT_TOKEN=$VAULT_TOKEN $VAULT token renew -address $VAULT_ADDR -client-cert $CERT -client-key $KEY
}

vault_puppet_login() {
    sudo -H $VAULT login -token-only -method=cert -path=cert -address=$VAULT_ADDR \
        -client-cert=$CERT -client-key=$KEY
}

vault_token_stash() {
    test -e ${VAULT_TOKENF} && mv -f$v ${VAULT_TOKENF} ${VAULT_TOKENF}-$$
}

vault_token_restore() {
    if test -e ${VAULT_TOKENF}; then
        rm -f$v ${VAULT_TOKENF}-$$
        return 0
    fi
    test -e ${VAULT_TOKENF}-$$ && mv -n$v ${VAULT_TOKENF}-$$ ${VAULT_TOKENF}
    rm -f$v ${VAULT_TOKENF}-$$
}

vault_print_token() {
    if [ -n "$VAULT_TOKEN" ]; then
        echo "$VAULT_TOKEN"
    elif [ -e "$VAULT_TOKENF" ]; then
        cat "$VAULT_TOKENF"
    fi
}

file_writable() {
    ! test -e "$1" || test -w "$1"
}

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --*=*)
            key="${cmd#--}"
            key="${key%%=*}"
            val="${cmd#*=}"
            eval ${key//-/_}="${val:-1}"
            ;;
        --no_*|--no-*)
            key="${cmd#--no[_-]}"
            eval ${key//-/_}=0
            ;;
        --*)
            key="${cmd#--}"
            eval ${key//-/_}=1
            ;;
        -*) echo >&2 "Unknown argument: $cmd"; exit 1;;
    esac
done

# shellcheck disable=SC2154
if ((xdebug)); then
    set -xv
    v=v
fi

VAULT=${VAULT:-$(command -v vault)}
export VAULT_ADDR="${VAULT_ADDR:-https://vault.service.consul:8200}"
export VAULT_TOKEN=$(vault print token)
VAULT_TOKENF="$HOME"/.vault-token

PUPPET_CONF=/etc/puppetlabs/puppet/puppet.conf
if ! certname=$(awk '/^certname/{print $(NF)}' $PUPPET_CONF) && [ -n "$certname" ]; then
    certname=$(hostname -f)
fi
CERT=/etc/puppetlabs/puppet/ssl/certs/${certname}.pem
KEY=/etc/puppetlabs/puppet/ssl/private_keys/${certname}.pem
SELF=$(mktemp -t vault-token.XXXXXX) || exit 1
# shellcheck disable=SC2064
trap "rm -f$v $SELF" EXIT INT QUIT TERM
if [ -n "$VAULT_TOKEN" ]; then
    if ! vault_lookup_self "$VAULT_TOKEN" >>$SELF 2>/dev/null; then
        unset VAULT_TOKEN
        vault_token_stash
        echo >&2 "INFO: Couldn't acquire existing token. Please unset the environment and rm ~/.vault-token if this fails"
    else
        if [ "$(jq -r .data.renewable $SELF)" = true ] && [ "$(jq -r .data.meta.cert_name $SELF)" = puppet ]; then
            if [[ $(jq -r .data.ttl $SELF) -gt 2700 ]]; then
                ((print_token)) && vault_print_token
                exit 0
            fi
            if vault_renew >/dev/null; then
                echo >&2 "INFO: Renewed your vault token"
                ((print_token)) && vault_print_token
                exit 0
            fi
            unset VAULT_TOKEN
            echo >&2 "WARN: Renewing your token didn't work"
            vault_token_stash
        fi
    fi
    ((xdebug)) && cat $SELF >&2
fi

if [ -n "$VAULT_TOKEN" ]; then
    vault_token_restore
    ((print_token)) && vault_print_token
    exit 0
fi

if VAULT_TOKEN=$(vault_puppet_login); then
    echo >&2 "INFO: Acquired new vault token"
    vault_token_restore
    if file_writable "$VAULT_TOKENF"; then
        echo >&2 "INFO: Replacing token in $VAULT_TOKENF"
        rm -f$v ${VAULT_TOKENF}
        touch ${VAULT_TOKENF}
        chmod 0600 ${VAULT_TOKENF}
        echo "$VAULT_TOKEN" >> ${VAULT_TOKENF}
    else
        echo >&2 "INFO: $VAULT_TOKENF not replaced, as it isn't writable"
    fi
    rm -f$v ${VAULT_TOKENF}-$$
    ((print_token)) && vault_print_token
    exit 0
fi
echo >&2 "ERROR: Authenticating with Vault"
vault_token_restore
exit 1
