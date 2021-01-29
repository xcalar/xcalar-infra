#!/bin/bash
set -e

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

MODEM_SSH_KEY=${MODEM_SSH_KEY:-"/home/thaining/.ssh/rt-ac66u"}
MODEM_IP=${MODEM_IP:-"10.10.1.1"}
MODEM_USER=${MODEM_USER:-"admin"}
MODEM_USB=${MODEM_USB:-"/tmp/mnt/depot/ASUS"}
BACKUP_REPO=${BACKUP_REPO:-"/home/thaining/backup"}
BACKUP_LOG=${BACKUP_LOG:-"/home/thaining/backup_report.txt"}

ssh -i $MODEM_SSH_KEY ${MODEM_USER}@${MODEM_IP} "${MODEM_USB}/nvram-save.sh -M" &> "$BACKUP_LOG"
scp -r -i $MODEM_SSH_KEY "${MODEM_USER}@${MODEM_IP}:${MODEM_USB}/backup/*" ${BACKUP_REPO} &>> "$BACKUP_LOG"
ssh -i $MODEM_SSH_KEY ${MODEM_USER}@${MODEM_IP} "/bin/rm -rf ${MODEM_USB}/backup/*" 

/usr/bin/find "$BACKUP_REPO" -mtime +30 -exec rm -rf {} \; &>> "$BACKUP_LOG"
