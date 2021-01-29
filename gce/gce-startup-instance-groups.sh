#!/bin/bash

export PATH=/usr/share/google:$PATH

CLOUDSDK_COMPUTE_ZONE="$(get_metadata_value zone)"
CLOUDSDK_COMPUTE_ZONE="${CLOUDSDK_COMPUTE_ZONE##*/}"
export CLOUDSDK_COMPUTE_ZONE

INSTANCE_TEMPLATE="$(get_metadata_value attributes/instance-template)"
INSTANCE_TEMPLATE="${INSTANCE_TEMPLATE##*/}"

INSTANCE_GROUP_POSTFIX="${HOSTNAME##*-}"
INSTANCE_GROUP="$(echo $HOSTNAME | sed -e 's/-'$INSTANCE_GROUP_POSTFIX'$//g')"

INSTANCES="$(gcloud compute instance-groups list-instances --sort-by name $INSTANCE_GROUP | grep ' RUNNING$' | awk '{print $1}')"

FACTS=/etc/facter/facts.d
mkdir -p $FACTS

echo "zone=$CLOUDSDK_COMPUTE_ZONE" >$FACTS/zone.txt
echo "instance_group=$INSTANCE_GROUP" >$FACTS/instance_group.txt
echo "instance_template=$INSTANCE_TEMPLATE " >$FACTS/instance_template.txt

idx=1
for ii in $INSTANCES; do
    if [ "$ii" == "$HOSTNAME" ]; then
        break
    fi
    ((idx++))
done
if [ "$ii" = "$HOSTNAME" ]; then
    echo >&2 "$HOSTNAME found in instance-group $INSTANCE_GROUP ($INSTANCES) at position $idx."
    echo "nodeid=$idx" >$FACTS/nodeid.txt
else
    rm -f $FACTS/nodeid.txt
fi
