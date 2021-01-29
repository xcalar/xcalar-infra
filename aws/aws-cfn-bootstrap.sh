#!/bin/bash

set +e
set -x

NUM_INSTANCES="${1:-1}"
INSTALLER_URL="${2}"

safe_curl () {
	curl -4 -L --retry 10 --retry-delay 3 --retry-max-time 60 "$@"
}

install_deps () {
    if test -e /etc/redhat-release; then
        chkconfig cfn-hup on
    else
        update-rc.d cfn-hup defaults
    fi
    export PATH=$PATH:/opt/aws/bin
    eval $(ec2-tags -s -i)
}

cfn_cmd () {
    if [ -n "$AWS_CLOUDFORMATION_STACK_NAME" ]; then
        "$@" --stack "$AWS_CLOUDFORMATION_STACK_NAME" --resource "$AWS_CLOUDFORMATION_LOGICAL_ID" --region "$AWS_DEFAULT_REGION"
    fi
}

install_deps


#http://169.254.169.254/2016-09-02/meta-data/instance-type
#http://169.254.169.254/2016-09-02/meta-data/ami-launch-index
ZONE="$(safe_curl http://169.254.169.254/2016-09-02/meta-data/placement/availability-zone)"

# Needed for AWS cli tools
export AWS_DEFAULT_REGION="${ZONE:0:-1}"

sed -i -e '/ puppet$/d' /etc/hosts
echo '172.31.6.119  puppet' | tee -a /etc/hosts


RETRY=5
while [ $RETRY -gt 0 ]; do
    /opt/puppetlabs/bin/puppet agent -t -v
    rc=$?
    if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then
        break
    fi
    RETRY=$((RETRY-1))
    echo >&2 "Puppet returned $rc .. retrying after a short wait... ($RETRY retries left)"
    sleep 5
done


eval $(ec2-tags -i -s)
CLUSTER=$AWS_CLOUDFORMATION_STACK_NAME

mount_efs () {
    mkdir -p /netstore
    if ! mountpoint -q /netstore; then
        sed -i '/netstore/d' /etc/fstab
        echo 'fs-d4d4237d.efs.us-west-2.amazonaws.com:/    /netstore    nfs4    nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2    0    0' | tee -a /etc/fstab
        mount /netstore
    fi
    RootPath=/netstore/cluster/$AWS_AUTOSCALING_GROUPNAME
    mkdir -p "$RootPath"
    chmod 0777 "$RootPath"
}

mount_xlrroot () {
    RootPath=/netstore/cluster/${CLUSTER}
    XLRROOT=/mnt/xcalar

    test -e ${RootPath}/sessions && rm -rf ${RootPath}
    mkdir -m 0777 -p ${RootPath} ${XLRROOT}
    chmod 0777 ${RootPath} ${XLRROOT}

    echo "${RootPath}     ${XLRROOT}     none    bind  0  0" | tee -a /etc/fstab

    mount ${XLRROOT}
}

aws_config() {
    mkdir -m 0700 -p ~/.aws
    mkdir -p ~/.aws/cli
    safe_curl -fL https://raw.githubusercontent.com/awslabs/awscli-aliases/master/alias -o ~/.aws/cli/aliases
    aws configure set default.s3.signature_version s3v4
    aws configure set default.s3.addressing_style path
    aws configure set default.region $AWS_DEFAULT_REGION
}

mount_efs
mount_xlrroot
aws_config

if [ -n "$INSTALLER_URL" ] && [ "$INSTALLER_URL" != "http://none" ]; then
    if [[ "$INSTALLER_URL" =~ ^http ]]; then
        safe_curl -fL "$INSTALLER_URL" -o /var/tmp/xcalar-install.sh
        bash -x /var/tmp/xcalar-install.sh --nostart --caddy --startonboot
    elif test -e "$INSTALLER_URL" ; then
        bash -x "$INSTALLER_URL" --nostart --caddy --startonboot
    fi
    rc=$?
    if [ $rc -ne 0 ]; then
        exit $rc
    fi
fi


IPS=()

until [ "${#IPS[@]}" -eq $NUM_INSTANCES ]; do
    INSTANCES=($(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${AWS_AUTOSCALING_GROUPNAME} --query 'AutoScalingGroups[].Instances[].InstanceId' --output text))
    IPS=($(aws ec2 describe-instances --instance-ids "${INSTANCES[@]}"  --query 'Reservations[].Instances[].PrivateDnsName' --output text | sort))
    [ "${#IPS[@]}" -eq $NUM_INSTANCES ] && break || sleep 15
done

(
 echo Constants.SendSupportBundle=true
 /opt/xcalar/scripts/genConfig.sh /etc/xcalar/template.cfg - "${IPS[@]}"
) | sed 's@^Constants.XcalarRootCompletePath=.*$@Constants.XcalarRootCompletePath='${XLRROOT}'@g' | tee /etc/xcalar/default.cfg

mkdir -p ${XLRROOT}/config
chown -R xcalar:xcalar ${XLRROOT}/config /etc/xcalar

if ! service xcalar start; then
    echo >&2 "Failed to start cluster"
fi

jsonData="{ \"defaultAdminEnabled\": true, \"username\": \"${AdminUsername:-xdpadmin}\", \"email\": \"${AdminEmail:-support@xcalar.com}\", \"password\": \"${AdminPassword:-Welcome1}\" }"
safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "http://127.0.0.1:12124/login/defaultAdmin/set"  || true
