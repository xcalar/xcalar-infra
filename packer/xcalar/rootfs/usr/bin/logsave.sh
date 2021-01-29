#!/bin/bash
set -e
set -a
source /var/lib/cloud/instance/ec2.env
eval $(ec2-tags -s)
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export AWS_DEFAULT_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
export NOW=$(date --utc +'%FT%TZ')
export TODAY=$(date --utc +'%Y/%m/%d')
export NODE_ID="${NAME#$AWS_CLOUDFORMATION_STACK_NAME-}"
export PREFIX=bootlogs/${TODAY}/$AWS_CLOUDFORMATION_STACK_NAME/${NOW}-${NODE_ID}-${INSTANCE_ID}

if [ -n "$LOGBUCKET" ]; then
    if [ -n "$LOGPREFIX" ]; then
        LOGPREFIX="${LOGPREFIX#/}"
        LOGPREFIX="${LOGPREFIX%/}"
    fi
	s3save() {
		aws s3 cp - s3://${LOGBUCKET}/${LOGPREFIX}/${PREFIX}-"$1"
	}
else
	mkdir -m 0700 -p /var/tmp/collect/$PREFIX
	s3save() {
		cat - > /var/tmp/collect/"${PREFIX}"-"$1"
	}
fi

export -f s3save

TMPDIR=/tmp/boot-$$
mkdir -m 0700 -p $TMPDIR
cd $TMPDIR
systemd-analyze plot | s3save bootchart.svg
systemd-analyze blame | s3save blame.txt
cloud-init collect-logs
mkdir cloud-init
tar zxf cloud-init.tar.gz --strip-components=1 -C cloud-init
tar czf - cloud-init | s3save cloud-init.tar.gz
cd -
rm -rf $TMPDIR
cd /var/log
for ii in user-data* cfn-* messages cloud-*; do
	gzip -c "$ii" | s3save "$ii".gz
done
tar czf - xcalar | s3save xcalar.tar.gz
exit 0
