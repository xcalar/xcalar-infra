#!/bin/bash
#
# Create a file ~/.resticpass containing your password or
# export RESTIC_PASSWORD_FILE pointing to a file containing your password
# By default the script will backup your $HOME to /netstore/restic/$USER/$HOSTNAME
# If you want it backed up somewhere else, set RESTIC_REPOSITORY to your
# preferred location. Please custom exclude wildcards into ~/.restic_excludes.txt
#
# Calling this script with any other arguments causes the base restic
# tool to be called with proper variables set. This is handy if you want to
# perform any other restic operations (like mounting a snapshot).
#
#
# It is best if you call this script from cron, daily. Use crontab -e and put
# something like this
#
# 5 6 * * * /home/abakshi/xcalar-infra/bin/restic.sh backup /home/abakshi
#
# To backup daily at 6:05am
#
# shellcheck disable=SC2046,SC2086,SC2206

set -e

USER=${USER:-$(id -un)}
HOME=${HOME:-$(getent passwd $(id -u) | awk -F: '{print $6}')}
HOST=${HOST:-$(hostname -s)}
BACKUP_BASE=${BACKUP_BASE:-/netstore/restic}
SCRIPT=$(basename $0)

if ! command -v restic >/dev/null; then
    echo >&2 "Unable to find restic executable. Try 'sudo apt-get install restic'"
    exit 1
fi

# One of the must be set
if [ -z "$RESTIC_PASSWORD" ] && [ -z "$RESTIC_PASSWORD_FILE" ] && [ -z "$RESTIC_PASSWORD_COMMAND" ]; then
    if test -s $HOME/.resticpass; then
        export RESTIC_PASSWORD_FILE=$HOME/.resticpass
        unset RESTIC_PASSWORD RESTIC_PASSWORD_COMMAND
    else
        echo >&2 "Must have ~/.resticpass or set RESTIC_PASSWORD_FILE to a valid file containing your password."
        echo >&2 "Use 'openssl rand -base64 18 | tee  ~/.resticpass' to generate a strong password in ~/.resticpass"
        echo >&2 "Then be sure to 'chmod 0400 ~/.resticpass' to prevent others from reading it and you from"
        echo >&2 "overwriting it."
        echo >&2 ""
        echo >&2 "Make a backup of the password!"
        echo >&2 ""
        exit 1
    fi
fi
if [ -n "$RESTIC_PASSWORD_FILE" ]; then
    if ! test -s "$RESTIC_PASSWORD_FILE"; then
        echo >&2 "You specified RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE but it's either empty or missing!"
        exit 1
    fi
    if [ "$(stat -c %a "$RESTIC_PASSWORD_FILE")" != 400 ]; then
        echo >&2 "WARNING: Your RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE permissions are too open"
        echo >&2 "Running 'chmod 0400 $RESTIC_PASSWORD_FILE'"
        if ! chmod 0400 $RESTIC_PASSWORD_FILE; then
            echo >&2 "ERROR: Failed to chmod 0400 $RESTIC_REPOSITORY"
            exit 1
        fi
    fi
fi


if [ -z "$RESTIC_REPOSITORY" ]; then
    if ! test -e "$BACKUP_BASE"; then
        echo >&2 "ERROR: BACKUP_BASE=$BACKUP_BASE doesn't exist"
        echo >&2 "Please set BACKUP_BASE properly"
        exit 1
    fi
    export RESTIC_REPOSITORY=${BACKUP_BASE}/$USER/$HOST
fi

if ! test -d "$RESTIC_REPOSITORY"; then
    if ! mkdir -p "$RESTIC_REPOSITORY"; then
        echo >&2 "ERROR: Failed to create $RESTIC_REPOSITORY. Please create manually"
        exit 1
    fi
fi
if ! test -e "$RESTIC_REPOSITORY/config"; then
    echo >&2 "Initializing new repository in $RESTIC_REPOSITORY ..."
    if ! restic init; then
        echo >&2 "ERROR: Failed to initialize $RESTIC_REPOSITORY. Please run 'restic init' manually"
        exit 1
    fi
fi
if ! test -w "$RESTIC_REPOSITORY"; then
    echo >&2 "ERROR: Don't have write access to $RESTIC_REPOSITORY. Please 'sudo chown $(id -u) $RESTIC_REPOSITORY'"
    exit 1
fi

if ! test -s $HOME/.restic_std_excludes.txt; then
    EXCLUDES=".venv* xcve* spark .git .m2 .tmp .direnv* buildOut* rootfs .cache .ccache *.deb *.rpm *.tar"
    EXCLUDES+=" *.tgz *.gz *.tar *.iso *.qcow2 *.img *.vmdk tdhtest xcalar*installer* node_modules tmp wrkDir build"
    echo -e "${EXCLUDES// /\\n}" > $HOME/.restic_std_excludes.txt
fi
touch $HOME/.restic_excludes.txt ## Put your custom exclusions here

ARGS=(--one-file-system --exclude-if-present=.nobackup --exclude-file=$HOME/.restic_std_excludes.txt)
ARGS+=(--exclude-file=$HOME/.restic_excludes.txt --host $HOST)

DAY=$(date +'%Y-%m-%d')
LOG=/var/tmp/restic-logs-$(id -u)/restic-${DAY}.log
mkdir -p $(dirname $LOG)

# Backup $HOME by default
if [ $# -eq 0 ]; then
    set -- backup "$HOME"
elif [ $# -eq 1 ]; then
    case "$1" in
        --install-cron)
            H=$((RANDOM % 8))
            M=$((RANDOM % 60))
            if (crontab -l | sed "\@$SCRIPT@d"; echo "$M $H * * * $(readlink -f ${BASH_SOURCE[0]}) backup $HOME")  | crontab -; then
                echo >&2 "Installed crontab to run $0 every day at $H:$M"
                exit 0
            fi
            echo >&2 "ERROR: Failed to install new crontab"
            exit 1
            ;;
        --uninstall-cron)
            if (crontab -l | sed "\@$SCRIPT@d") | crontab -; then
                echo >&2 "Uninstalled from crontab"
                exit 0
            fi
            echo >&2 "ERROR: Failed to uninstall from crontab"
            exit 1
            ;;
        --help|-h|-help)
            restic -h
            echo >&2 ""
            echo >&2 "Additional $SCRIPT options:"
            echo >&2 ""
            echo >&2 "      --install-cron      Install $SCRIPT into daily crontab"
            echo >&2 "      --uninstall-cron    Uninstall $SCRIPT into daily crontab"
            echo >&2 ""
            exit 0
            ;;
        backup)
            set -- backup "$HOME"
            ;;
    esac
fi

case "$1" in
    backup)
        shift
        restic backup "${ARGS[@]}" "$@" 2>&1 | tee -a $LOG
        rc=${PIPESTATUS[0]}
        if [ $rc -ne 0 ]; then
            echo >&2 "ERROR: restic backup encountered an error. See log $LOG"
            exit $rc
        fi
        restic forget --keep-daily 21 --keep-weekly 9 --keep-monthly 13 --keep-yearly 2 --prune 2>&1 | tee -a $LOG
        rc=${PIPESTATUS[0]}
        if [ $rc -ne 0 ]; then
            echo >&2 "ERROR: restic forget encountered an error. See logs in $LOG"
            echo
            exit $rc
        fi
        ;;
    *)
        restic "$@"
        ;;
esac
