#!/bin/bash
#
# Script to manage AWS credentials generated in Vault. Supports multiple profiles,
# caching, and is a plugin to the awscli.
#
# In the awscli credentials configuration, ~/.aws/credentials, you can specify keys
# directly, or you can specify a credentials provider as an external script that is
# responsible for providing awscli with valid credentials. This is such a script.
#
# ; from ~/.aws/credentials
# [vault]  ; <-- or any other profile name
# credential_process=/home/abakshi/bin/vault-aws-credentials-provider.sh --path aws-xcalar/sts/poweruser
#
# From then on when calling `awscli --profile vault`, this script is called, which
# in turn calls vault

# <-----------------------------------------------------------------------------
# Vault gives us this format:
#
# {
#   "request_id": "9f8f7133-e341-5cfb-437f-f98646bf8d0f",
#   "lease_id": "aws/sts/deploy/d177f27b-9251-d261-956d-66b59428e79c",
#   "lease_duration": 3599,
#   "renewable": false,
#   "data": {
#     "access_key": "ASIAJEGZPHIMPZHJHIMQ",
#     "secret_key": "6chW+auMR53SFjrlhknxQohogp5xe7BFYuC8Kk23",
#     "security_token": "FQoDYXdzENj//////////wEaDNSxT0hN2kESqT1U/iL6AVrZFwm"
#   },
#   "warnings": null
# }
#
# Aws wants this (via https://docs.aws.amazon.com/cli/latest/topic/config-vars.html#sourcing-credentials-from-external-processes):
#
# {
#   "Version": 1,
#   "AccessKeyId": "",
#   "SecretAccessKey": "",
#   "SessionToken": "",
#   "Expiration": ""
# }

FILE=""
PROG="$(basename "$0" .sh)"
VAULTCACHE_BASE="$HOME/.cache/$PROG"
LOG="$VAULTCACHE_BASE/log.txt"
TTL=4h
ACCOUNT="${ACCOUNT:-$(cat ${VAULTCACHE_BASE}/account 2>/dev/null || echo aws-xcalar)}"
TYPE="sts"
ROLE="${ROLE:-$(cat ${VAULTCACHE_BASE}/role 2>/dev/null || echo poweruser)}"
PROFILE="${PROFILE:-$(cat ${VAULTCACHE_BASE}/profile 2>/dev/null || echo vault)}"
CLEAN=false
EXPORT_ENV=false
EXPORT_PROFILE=false
INSTALL=false
VAULT_WIKI='https://xcalar.atlassian.net/wiki/spaces/EN/pages/8749395/Vault'
BREW_WIKI='https://xcalar.atlassian.net/wiki/spaces/EN/pages/8749196/Homebrew'
UNMET_DEPS=()
AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
AWS_PROFILE_SAVE="${AWS_PROFILE}"
VAULT_AWS_ACCOUNTS=(aws-xcalar aws-xcalar-trials aws-xcalar-poc aws-test aws-prod aws-pegasus)
unset AWS_PROFILE

usage() {
    cat <<EOF >&2

     $(basename $0) [--account ACCOUNT] [--role ROLE]
        [--install] [--profile PROFILE] [--ttl NUM] [--clean]

    --account  ACCOUNT   AWS Account to use (default $ACCOUNT (valid: ${VAULT_AWS_ACCOUNTS[*]}))
    --role     ROLE      AWS Role (default: $ROLE)
    --install            Install into ~/.aws/credentials to have awscli automatically retrieve keys
    --ttl      TTL       TTL for token, min is 15m, max is 12h (default: $TTL)
    --profile  PROFILE   AWS CLI Profile to populate from ~/.aws/config (default: $PROFILE)

    -c|--clean           Clean all existing cached vault data (if any)

    Advanced options ...
      [--check] [--path PATH] [-e|--export-env] [--export-profile]
        [-f|--file FILE|-]

    --check              Sanity check your installation
    --path     PATH      Complete vault path to use (default: \$ACCOUNT/\$TYPE/\$ROLE = $ACCOUNT/$TYPE/$ROLE)
    -f|--file    FILE|-  Read existing credentials from FILE or - (stdin)
    -e|--export-env      Print eval'able AWS environment variables that you can use for auth (eval, or add to ~/.bashrc)
    --export-profile     Print credentials in AWS credential format (you can add them to ~/.aws/credentials)
    --unset-profile      Print eval'able settings to reset local shell env
EOF
    say "$*"
    exit 2
}

log() {
    echo "[$(date +%FT%T%z) $USER@$HOSTNAME $PROG $$] $*" >> $LOG
    if ! test -t 2; then
        say "[$(date +%FT%T%z) $USER@$HOSTNAME $PROG] $*"
    fi
}

say() {
    echo >&2 "$1"
}

die() {
    if [ -z "$1" ]; then
        log "Unspecified error"
        exit 1
    fi

    log "ERROR: $1"
    log "die: $*"
    say
    say "For more information and detailed instructions see the Vault Wiki:"
    say ""
    say "$VAULT_WIKI"
    say ""
    exit ${2:-1}
}

if [[ $OSTYPE =~ darwin ]]; then
    please_install() {
        say
        say "You need '$1'. The easiest way to install '$1' is via 'brew'"
        log "Checking brew"
        if ! command -v brew >/dev/null && [ "$brew_warn" != true ]; then
            brew_warn=true
            say "Alas, you need to install 'brew', a package manager for OSX"
            say
            echo >&2 '  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
            say
            say "For more information and detailed instructions on Brew see:"
            say "$BREW_WIKI"
            say
            say "Once you have it, run:"

        else
            say "Try running the following:"
        fi

        say
        say " brew update"
        say " brew install ${2:-$1}"
    }
    date() {
        if command -v gdate >/dev/null; then
            gdate "$@"
        else
            date "$@"
        fi
    }
    stat() {
        gstat "$@"
    }
    sed() {
        gsed "$@"
    }
    readlink() {
        greadlink "$@"
    }
    sha256sum() {
        shasum -a 256
    }
else
    please_install() {
        say
        if command -v apt-get >/dev/null; then
            say "You need to install $1. Try 'sudo apt-get update && sudo apt-get install -y ${2:-$1}'"
        else
            say "You need to install $1. Try 'sudo yum install -y --enablerepo=\"xcalar-*\" ${2:-$1}'"
        fi
    }
fi

please_have() {
    if ! command -v "$1" >/dev/null; then
        please_install "$@"
        UNMET_DEPS+=("$1")
        return 1
    fi
}

print_clean_env() {
    env | sed '/^BASH_FUNC/,/^}/d' | grep -Ev '(COLOR|_fzf|SECRET|PASS|CRED)' | sort
}

cvault() {
    (
    set +x
    local vault_token
    if ! vault_token=$(vault print token); then
        die "Failed to retrieve your local vault token. Are you logged in? vault auth -method=ldap username=jsmith"
    fi
    if [ -z "$vault_token" ]; then
        die "Failed to find VAULT_TOKEN environment or ~/.vault-token file. Are you logged in?"
    fi
    local uri="$1"
    shift
    local vthash=$(sha256sum <<< "${vault_token}" | awk '{print $1}')
    log curl -sL -H "X-Vault-Request: true" -H "X-Vault-Token: [vthash: ${vthash}]" "${VAULT_ADDR}/v1/${uri}" "$@"
    curl -sL -H "X-Vault-Request: true" -H "X-Vault-Token: $vault_token" "${VAULT_ADDR}/v1/${uri}" "$@"
    ) || die "Failed when calling cvault $*"
}

vault_health() {
    local status
    if status="$(
        set -o pipefail
        cvault sys/health | jq -r .sealed
    )" && [ "$status" = false ]; then
        return 0
    fi
    return 1
}

aws_configure() {
    local value
    value="$(aws configure get $1)"
    if [ $? -eq 0 ] && [ -n "$value" ]; then
        return 0
    fi
    aws configure set $1 $2
}

has_space() {
    [[ $1 =~ [[:space:]] ]]
}

vault_install_credential_helper() {
    vault_sanity
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"
    aws_configure default.region $AWS_DEFAULT_REGION
    aws_configure default.s3.signature_version s3v4
    aws_configure default.s3.addressing_style auto

    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    local filen="$(basename "${BASH_SOURCE[0]}")"

    touch ${AWS_SHARED_CREDENTIALS_FILE}
    sed -i.bak '/^\['$PROFILE'\]/,/^$/d' ${AWS_SHARED_CREDENTIALS_FILE}
    sed -i.bak '/^\[profile '$PROFILE'\]/,/^$/d' ${AWS_CONFIG_FILE}

    local q=''
    if has_space "${dir}/${filen}"; then
        q='"'
    fi
    cat >>${AWS_SHARED_CREDENTIALS_FILE} <<EOF
[$PROFILE]
credential_process = ${q}${dir}/${filen}${q} --path $AWSPATH

EOF
    unset AWS_PROFILE
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_ACCESS_KEY_ID
    if ! aws --profile "$PROFILE" sts get-caller-identity --output json; then
        die "Failed to get your identity from AWS for profile $PROFILE"
    fi

    say "SUCCESS"
    say
    if [ "$PROFILE" = default ]; then
        say "   aws <cmd>"
        say ""
    else
        say "   aws --profile $PROFILE <cmd>"
        say ""
        say "To avoid having to add '--profile $PROFILE' to every awscli command, run the following in your shell:"
        say "   export AWS_PROFILE=$PROFILE"
        say ""
        say "To persist this setting to new shells, also add that line to your ~/.bashrc"
        say ""
    fi
    echo "$ACCOUNT" >"${VAULTCACHE_BASE}/account"
    echo "$ROLE" >"${VAULTCACHE_BASE}/role"
    echo "$PROFILE" >"${VAULTCACHE_BASE}/profile"
}

vault_sanity() {
    say "Sanity checking your vault installation ..."
    local progs="jq vault curl" prog any_missing=0
    for prog in $progs; do
        if ! please_have $prog; then
            :
        fi
    done
    if [[ $OSTYPE =~ darwin ]]; then
        progs="gsed gdate greadlink gstat"
        for prog in $progs; do
            if ! please_have $prog "coreutils"; then
                break
            fi
        done
    fi
    echo "1..7"
    if [ "${#UNMET_DEPS[@]}" -gt 0 ]; then
        echo "not ok    1  - missing dependencies ${UNMET_DEPS[*]}"
        die "You have unmet dependencies: ${UNMET_DEPS[*]}"
    fi
    echo "ok    1  - have all dependencies"
    local -a aws_version
    if ! aws_version=($(
        set -o pipefail
        aws --version 2>&1 | sed -E 's@^aws-cli/([0-9\.]+).*$@\1@g' | tr . ' '
    )); then
        echo "not ok    2  - awscli 15.40 or higher"
        die "awscli needs to be version 15.40 or higher. Use virtualenv and pip install -U awscli."
    fi
    if [ ${aws_version[0]} -eq 2 ]; then
        echo "ok    2  - awscli v2"
    else
        if [ ${aws_version[1]} -lt 15 ]; then
            echo "not ok    2  - awscli 15.40 or higher"
            die "awscli needs to be version 15.40 or higher. Use virtualenv and pip install -U awscli."
        elif [ ${aws_version[1]} -eq 15 ] && [ ${aws_version[2]} -lt 40 ]; then
            echo "not ok    2  - awscli 15.40 or higher"
            die "awscli needs to be version 15.40 or higher. Use virtualenv and pip install -U awscli."
        fi
        echo "ok    2  - awscli 15.40 or higher"
    fi

    if [ -z "$VAULT_ADDR" ]; then
        echo "not ok    3  - VAULT_ADDR is set"
        die "VAULT_ADDR not set. Please set 'export VAULT_ADDR=https://vault.service.consul:8200' to your ~/.bashrc or ~/.bash_profile"
    fi
    echo "ok    3  - VAULT_ADDR is set"
    if ! curl -o /dev/null -k -fsS "$VAULT_ADDR"; then
        echo "not ok    4  - failed to connect to vault"
        die "Failed to connect to VAULT_ADDR=$VAULT_ADDR"
    fi
    if ! curl -o /dev/null -fsS "$VAULT_ADDR"; then
        echo "not ok    4  - failed to securely connect to vault"
        die "Failed to connect to VAULT_ADDR=$VAULT_ADDR in a secure fashion. Please check http://wiki.int.xcalar.com/mediawiki/index.php/Xcalar_Root_CA"
    fi
    echo "ok    4  - connected to vault"
    local display_name
    if ! display_name=$(
        set -o pipefail
        cvault auth/token/lookup-self | jq -r .data.display_name
    ); then
        echo "not ok    5  - failed to look up your token"
        die "Failed to look you up. Are you logged into vault? Try 'vault login -method=ldap username=jdoe'. Your username is your LDAP username (usually the part before @xcalar.com in your email)"
    fi
    echo "ok    5  - verified your token with vault (display_name: $display_name)"
    if ! vault_health; then
        echo "not ok    6  - checked vault health"
        die "Failed to get 'vault health', or vault is sealed"
    fi
    echo "ok    6  - checked vault health"
    if cvault auth/token/lookup-self | jq -r '.data|[.policies[],.identity_policies[]]' | grep -q aws; then
        echo "not ok  7  - not a member of aws enabled group in LDAP. Check with IT."
    else
        echo "ok  7  - member of aws enabled group"
    fi

}

iso2unix() {
    date -u -d "$1" +%s
}

unix2iso() {
    date -u -d @$1 +%FT%TZ
}

json_value() {
    local key="$1" value
    shift
    if ! value=$(jq -r "$key" "$@"); then
        return 1
    fi
    if [ "$value" = null ]; then
        return 1
    fi
    echo "$value"
}

expiration_ts() {
    local file_time=$(stat -c %Y "$1")
    local expiration=$((file_time + $2))
    unix2iso $expiration
}

expiration_json() {
    json_value .expiration "$@" 2>/dev/null
}

lease_duration_json() {
    json_value .lease_duration "$@" 2>/dev/null
}

vault_update_expiration() {
    local lease_duration expiration
    if ! lease_duration=$(lease_duration_json "$1"); then
        return 1
    fi
    if ! expiration=$(date -d "$lease_duration seconds" +%s); then
        return 1
    fi
    jq -r '. + { expiration: '$expiration'}' "$1"
}

vault2aws() {
    local ttl expiration
    if ! ttl="$(lease_duration_json "$1")"; then
        say "Failed to get lease_duration from $1"
        ttl=''
    fi
    if [ -z "$ttl" ] || [ "${ttl:0:1}" = 0 ]; then
        jq -M -c -r '{ Version: 1, AccessKeyId: .data.access_key, SecretAccessKey: .data.secret_key }   ' $1
    else
        if expiration=$(expiration_json "$1"); then
            local u2i=$(unix2iso $expiration)
            jq -M -c -r '{ Version: 1, AccessKeyId: .data.access_key, SecretAccessKey: .data.secret_key, SessionToken: .data.security_token, Expiration: "'$u2i'"}   ' $1
        fi
    fi
}

vault_render_file() {
    local file="$1" tmp=''
    if [ -z "$file" ] || [ "$file" = - ]; then
        tmp=$(mktemp -t vaultXXXXXX.json)
        chmod 0600 $tmp
        cat - >"$tmp"
        file="$tmp"
    fi
    if $EXPORT_ENV; then
        echo " AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
        echo " AWS_ACCESS_KEY_ID=\"$(jq -r .data.access_key $file)\""
        echo " AWS_SECRET_ACCESS_KEY=\"$(jq -r .data.secret_key $file)\""
        echo " AWS_SESSION_TOKEN=\"$(jq -r .data.security_token $file)\""
        echo " export AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"
    elif $EXPORT_PROFILE; then
        echo "[$PROFILE]"
        echo "aws_access_key_id = $(jq -r .data.access_key $file)"
        echo "aws_secret_access_key = $(jq -r .data.secret_key $file)"
        echo "aws_session_token = $(jq -r .data.security_token $file)"
        echo
    else
        vault2aws "$file"
    fi

    test -z "$tmp" || rm -f "$tmp"
}

main() {
    mkdir -p "${VAULTCACHE_BASE}"
    log "Args: $*"
    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            -h | --help) usage ;;
            -i | --install) INSTALL=true ;;
            --check)
                vault_sanity
                exit $?
                ;;
            --account)
                ACCOUNT="${1#aws-}"
                ACCOUNT="aws-${ACCOUNT}"
                shift
                ;;
            --role)
                ROLE="$1"
                shift
                ;;
            --type)
                TYPE="$1"
                shift
                ;;
            -c | --clean) CLEAN=true ;;
            -f | --file)
                FILE="$1"
                shift
                ;;
            --path)
                AWSPATH="$1"
                shift
                ;;
            -e | --export-env) EXPORT_ENV=true ;;
            --export-profile) EXPORT_PROFILE=true ;;
            --unset-profile)
                echo 'unset AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID AWS_SESSION_TOKEN'
                ;;
            --profile)
                PROFILE="$1"
                shift
                ;;
            --ttl)
                TTL="$1"
                shift
                ;;
            --) break ;;
            *) usage "Unknown argument $cmd" ;;
        esac
    done
    if $CLEAN; then
        : "${VAULTCACHE_BASE?VAULTCACHE_BASE must be set}"
        say "Clearing cached vault data in $VAULTCACHE_BASE .."
        rm -r -- "${VAULTCACHE_BASE:?}/*"
        exit $?
    fi
    ACCOUNT="${ACCOUNT#aws-}"
    ACCOUNT="aws-${ACCOUNT}"
    if [ -n "$FILE" ]; then
        vault_render_file "$FILE"
        exit $?
    fi
    if ! vault_health; then
        die "Failed to get vault status"
    fi

    test -e "$(dirname ${AWS_SHARED_CREDENTIALS_FILE})" || mkdir -m 0700 "$(dirname ${AWS_SHARED_CREDENTIALS_FILE})"
    if [ -z "$AWSPATH" ]; then
        AWSPATH="$ACCOUNT/$TYPE/$ROLE"
    fi
    AWSPATH="aws-${AWSPATH#aws-}"
    if $INSTALL; then
        vault_install_credential_helper
        exit $?
    fi
    VAULTCACHE="${VAULTCACHE_BASE}/${AWSPATH}.json"
    mkdir -m 0700 -p "$(dirname $VAULTCACHE)"
    export TMPDIR="$HOME/.aws/tmp"
    mkdir -m 0700 -p "$TMPDIR"
    TMP="$(mktemp ${TMPDIR}/vaultXXXXXX.json)"
    trap "rm -f $TMP" EXIT
    if [ -s "$VAULTCACHE" ]; then
        NOW=$(date +%s)
        if EXPIRATION=$(expiration_json "$VAULTCACHE" 2>/dev/null); then
            if [[ $EXPIRATION == 0 ]] || [[ $((EXPIRATION - NOW)) -gt 300 ]]; then
                vault_render_file "$VAULTCACHE"
                exit $?
            fi
        fi
    fi
    rm -f -- "$VAULTCACHE"

    case "$TYPE" in
        sts) cvault "$AWSPATH" -d '{"ttl": "'$TTL'"}' -X POST >"$TMP" ;;
        creds) cvault "$AWSPATH" -d '{"ttl": "'$TTL'"}' -X GET >"$TMP" ;;
        *) die "Unknown type of path $AWSPATH" ;;
    esac
    if [ $? -ne 0 ]; then
        echo >&2 "ERROR: Failed to get valid vault creds for $AWSPATH"
        echo >&2 "Check ~/.vault-token, VAULT_TOKEN and $TMP"
        echo >&2 "VAULT_ADDR=$VAULT_ADDR"
        exit 1
    fi
    local errors
    errors=$(jq -r .errors[] < "$TMP" 2>/dev/null || true)
    if [ -n "$errors" ]; then
        echo >&2 "*********"
        echo >&2 "ERROR: $(basename $0) encountered this error:"
        echo >&2
        echo >&2 " --> " "$errors"
        echo >&2 ""
        echo >&2 ""
        echo >&2 " Please run $0 --check to make sure you have vault setup properly"
        echo >&2 ""

        if [[ "$errors" =~ 'no handler for route' ]]; then
            echo >&2
            echo >&2 "      Are you sure '${AWSPATH%%/*}' is a valid AWS alias for an account?"
        fi
        echo >&2
        echo >&2 "*********"
        die
    fi

    if ! vault_update_expiration "$TMP" > "${TMP}.2"; then
        cat "$TMP" >&2
        rm -f "${TMP}.2"
        die "Failed to parse expiration of in $TMP"
    fi
    mv -f "${TMP}.2" "$TMP"

#    LEASE_DURATION=$(jq -r .lease_duration "$TMP")
#    if [ $? -eq 0 ] && [ -n "$LEASE_DURATION" ]; then
#        EXPIRATION=$(date -d "$LEASE_DURATION seconds" +%s)
#        jq -r '. + { expiration: '$EXPIRATION'}' "$TMP" >"${TMP}.2" \
#            || die "Failed to save converted vault credentials"
#        mv "${TMP}.2" "$TMP"
#    fi

    if ! vault_render_file "$TMP"; then
        cat "$TMP" >&2
        die "Failed to render $TMP"
    fi
    mv "$TMP" "$VAULTCACHE"
}

main "$@"
