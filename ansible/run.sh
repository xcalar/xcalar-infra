#!/bin/bash

if test -z "$VIRTUAL_ENV"; then
    if ! . ~/.local/lib/xcalar-infra/bin/activate; then
        echo >&2 "Please run make from $PWD/.."
        exit 1
    fi
fi

parse_cmd () {
    while test $# -gt 0; do
        local cmd="$1"
        shift
        case "$cmd" in
            -l|--limit) GROUP="$1"; shift;;
        esac
    done
}

# Unused
ssh_auth () {
    #export SSHPASS="$(awk '/ansible_ssh_pass/{print $2}' group_vars/$GROUP)"
    if [ -z "$SSHPASS" ]; then
        export SSHPASS="$(grep -Eow 'ansible_ssh_pass=[^ ]*' inventory/hosts | cut -d'=' -f2)"
    fi
    if [ -n "$SSHPASS" ]; then
        ./pass.exp ansible-playbook --ssh-common-args "-oPubkeyAuthentication=no" -i inventory/hosts --ask-pass --ask-become-pass --become "$@"
    else
        ansible-playbook --ssh-common-args "-oPubkeyAuthentication=no" -i inventory/hosts  --become "$@"
    fi
}

export ANSIBLE_HOST_KEY_CHECKING=False
parse_cmd "$@"
ssh_auth "$@"
#ansible-playbook --ssh-common-args '-oPubKeyAuthentication=no' -i inventory/hosts  --become "$@"
exit

