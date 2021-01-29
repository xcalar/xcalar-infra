#!/bin/bash

set -e

user_action() {
    local action="$1"
    shift
    local name="$1" email="$2" pass="$3"
    shift 3
    case "$action" in
        create)
            az ad user create --user-principal-name "$email" --display-name "$name" --password "$pass"
            ;;
        *) echo >&2 "ERROR: Unknown operation $action"; exit 1;;
    esac
}

ACTION="${1?Need to specify action}"

IFS=$'\n'
for ii in $(<users.txt); do
    echo $ii | while IFS=',' read A B C; do
        user_action $ACTION $A $B $C
    done
done
