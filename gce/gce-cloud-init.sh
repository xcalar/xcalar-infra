#!/bin/bash

metadata() { curl -fsL --connect-timeout 1 -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/"$1"; }
attr() { metadata "instance/attributes/$1"; }

if test -e /.xcalar-init; then
    exit 0
fi

if ! NAME=$(metadata instance/name); then
  NAME=$(hostname -s)
fi
BASENAME="${NAME%-[0-9]*}"
if ! CLUSTER=$(attr cluster); then
  CLUSTER="$BASENAME"
fi

if ! COUNT=$(attr count); then
  COUNT=1
fi

if ! EPHEMERAL=$(attr ephemeral_disk); then
    EPHEMERAL=/ephemeral/data
fi
if LICENSE="$(attr license)"; then
    if [ -n "$LICENSE" ]; then
        echo "$LICENSE" | base64 -d | gzip -dc > /etc/xcalar/XcalarLic.key
        chown xcalar:xcalar /etc/xcalar/XcalarLic.key
    fi
fi

LOCALCFG=/etc/xcalar/localcfg.cfg
CONFIG=/etc/xcalar/default.cfg

if CONFIG_DATA="$(attr config)"; then
    echo "$CONFIG_DATA" > "$LOCALCFG"
fi

if [[ $COUNT -gt 1 ]]; then
	XLRROOT=/mnt/xcalar
	NODE_ID="${NAME#${BASENAME}-}"

    if ! NFS_SHARE=$(attr nfs); then
        NFS_SHARE=nfs:/srv/share/nfs/cluster/$CLUSTER
        if [ $NODE_ID -eq 1 ]; then
            mkdir -p /mnt/nfs
            mount -t nfs -o defaults nfs:/srv/share/nfs/ /mnt/nfs
            mkdir -p -m 1777 /mnt/nfs/cluster/$CLUSTER
            umount /mnt/nfs
        fi
    fi

	sed -i '\@'$XLRROOT'@d' /etc/fstab
	echo "$NFS_SHARE $XLRROOT nfs defaults,nofail 0 0" >> /etc/fstab
	mkdir -m 1777 -p $XLRROOT
	until mount $XLRROOT; do
        sleep 2
        echo >&2 "Waiting for NFS: $NFS_SHARE"
    done

	if ! test -e "$LOCALCFG"; then
        /opt/xcalar/scripts/genConfig.sh  /etc/xcalar/template.cfg - $(eval echo ${NAME%-[0-9]*}-{1..$COUNT}) > $LOCALCFG
    fi
else
	XLRROOT=/var/opt/xcalar
	mkdir -m 1777 -p $XLRROOT
	NODE_ID=1
	if ! test -e "$LOCALCFG"; then
        /opt/xcalar/scripts/genConfig.sh  /etc/xcalar/template.cfg - $NAME > $LOCALCFG
    fi
fi
chmod 1777 $XLRROOT
chown -R xclar:xcalar $XLRROOT || true

sed -i 'd/SWAP/' /etc/sysconfig/ephemeral-disk
echo 'LV_SWAP_SIZE=MEMSIZE' >> /etc/sysconfig/ephemeral-disk
rm -f /run/ephemeral-disk
ephemeral-disk || true
if mountpoint -q $EPHEMERAL; then
    SERDES=$EPHEMERAL/serdes
    mkir -p -m 1777 $SERDES
    chown xcalar:xcalar $SERDES
    sed -i --follow-symlinks -e '5i Constants.XdbSerDesMode=2' -e '5i Constants.XdbLocalSerDesPath='$SERDES $LOCALCFG
else
    sed -i '/XdbSerDes/d; /XdbLocalSerDes/d' $LOCALCFG
fi
sed -i "s,Constants.XcalarRootCompletePath=.*$,Constants.XcalarRootCompletePath=$XLRROOT," $LOCALCFG
ln -sfn $LOCALCFG $CONFIG
chown xcalar:xcalar $LOCALCFG $CONFIG || true

if [[ $NODE_ID -eq 1 ]]; then
  mkdir -m 0700 -p $XLRROOT/config || true
  echo '{"username": "xdpadmin",  "password": "9021834842451507407c09c7167b1b8b1c76f0608429816478beaf8be17a292b",  "email": "info@xcalar.com",  "defaultAdminEnabled": true}' > $XLRROOT/config/defaultAdmin.json
  chmod 0600 $XLRROOT/config/defaultAdmin.json
  if ! test -e $XLRROOT/config/authorized_keys; then
      ssh-keygen -t ed25519 -N '' -f $XLRROOT/config/id_ed25519
  fi
  chown -R xcalar:xcalar $XLRROOT/config
  yum install -y ansible
  echo $(eval echo ${NAME%-[0-9]*}-{1..$COUNT}) | tee /etc/ansible/hosts
  curl https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg | \
      sed -r 's/^[#]?host_key_cecking.*$/host_key_cecking = True/' | \
      sed -r 's/^[#]?forks.*/forks = 50/' > /etc/ansible/ansible.cfg
fi

if lspci | grep '3D controller' | grep -q 'NVIDIA'; then
    echo >&2 "NVIDIA Detected"
    modprobe -a nvidia || true
    /usr/local/bin/nvidia-check.sh || true
fi

until test -e $XLRROOT/config/defaultAdmin.json; do
	sleep 3
	echo >&2 "Waiting for defaultAdmin ..."
done

mkdir -p -m 700 ~xcalar/.ssh
cat $XLRROOT/config/*.pub >> ~xcalar/.ssh/authorized_keys
chmod 0600 ~xcalar/.ssh/authorized_keys
chown -R xcalar:xcalar ~xcalar/.ssh

systemctl daemon-reload
systemctl enable xcalar
systemctl start xcalar
rc=$?
if [ $rc -eq 0 ]; then
    echo "Successfully started xcalar"
fi
touch /.xcalar-init
exit $rc
