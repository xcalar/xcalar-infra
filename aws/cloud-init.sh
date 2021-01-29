#!/bin/bash
#
# AWS Ec2 Cloud-init script to mount EFS
#

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

say () {
    echo >&2 "$*"
}

command_exists () {
    command -v "$1" &>/dev/null
}

pkg_install () {
    if command_exists yum; then
        if [ -z "$did_update" ]; then
            yum update -y
            did_update=1
        fi
        yum install -y "$@"
    elif command_exists apt-get; then
        if [ -z "$did_update" ]; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            did_update=1
        fi
        apt-get install -y "$@"
    else
        say "Unknown OS. Neither yum nor apt-get found"
        return 1
    fi
}

get_metadata () {
    curl -s "http://169.254.169.254/latest/meta-data/$1"
}

if ! command_exists curl; then
    pkg_install curl
fi

pip install -U awscli

XC_AZ="$(get_metadata placement/availability-zone)"
XC_REGION="${XC_AZ%%[a-z]}"
XC_INSTANCEID="$(get_metadata instance-id)"
XC_LAUNCHINDEX="$(get_metadata ami-launch-index)"
XC_LOCALIPV4="$(get_metadata local-ipv4)"
export AWS_DEFAULT_REGION=$XC_REGION
TAGS=/etc/profile.d/ec2tags.sh

pip install -U awscli
hash -r

aws ec2 describe-tags --filter Name=resource-id,Values=$XC_INSTANCEID --query 'Tags[].[Key,Value]' --output text | sed -Ee 's/^([^\s]+)\s+(.*)$/EC2TAG_\U\1=\E"\2"/g' > $TAGS
. $TAGS

if [ -n "$EC2TAG_FSID" ]; then
    EFSNAME="$(aws efs describe-file-systems --file-system-id "$EC2TAG_FSID" --query 'FileSystems[].Name' --output text)"
    if [ $? -ne 0 ] || [ -z "$EFSNAME" ]; then
        EC2TAG_FSID=
        sed -i -e '/EC2TAG_FSID/d' $TAGS
    fi
fi

if [ -n "$EC2TAG_FSID" ]; then
    XC_NFSHOST="${XC_AZ}.${EC2TAG_FSID}.efs.${XC_REGION}.amazonaws.com"
else
    XC_NFSHOST="${EC2TAG_NFSHOST:-nfs.aws.xcalar.com}"
fi

XC_NFSIP="$(nslookup $XC_NFSHOST | awk '/Address:/{print $2}' | tail -1)"
sed -i -e '/#cloud_init$/d' /etc/hosts /etc/fstab
echo "$XC_NFSIP		nfs   #cloud_init" | tee -a /etc/hosts >/dev/null
cat >> /etc/fstab <<EOF
nfs:/srv/share/data	/mnt/data	     nfs vers=4.1,defaults 	0	0	#cloud_init
nfs:/srv/share/nfs 	/mnt/nfs   	     nfs vers=4.1,defaults 	0	0	#cloud_init
nfs:/srv/datasets 	/netstore/datasets   nfs vers=4.1,defaults 	0	0	#cloud_init
EOF
DIRS="/mnt/data /mnt/nfs /netstore/datasets"
for mdir in $DIRS; do
    mkdir -p $mdir
    if ! mountpoint -q $mdir; then
        mount $mdir
    else
        mount -oremount $mdir
    fi
done

if [ -n "$EC2TAG_CLUSTER" ]; then
    mkdir -p /mnt/xcalar /mnt/nfs/cluster/${EC2TAG_CLUSTER}
    cat >> /etc/fstab <<-EOF
	nfs:/srv/share/nfs/cluster/$EC2TAG_CLUSTER /mnt/xcalar nfs vers=4.1,defaults  0   0  #cloud_init
	EOF
    if ! mountpoint -q /mnt/xcalar; then
        mount /mnt/xcalar
    else
        mount -oremount /mnt/xcalar
    fi
    aws --region us-west-2 ec2 describe-instances --filters Name=instance-state-name,Values=running,Name=tag:Cluster,Values=$EC2TAG_CLUSTER --query 'Reservations[].Instances[].[PrivateIpAddress,Tags[?Key==`Name`].Value[]]' --output text | sed '$!N;s/\n/ /' | grep -v '^None' | xargs -n1 -I {} printf "%s  #cloud_init\n" "{}" | tee -a /etc/hosts
fi

if [ -n "$EC2TAG_URL" ]; then
    curl -sSL "$EC2TAG_URL" > /tmp/xcalar-installer.sh
    chmod +x /tmp/xcalar-installer.sh
    mkdir -p /etc/xcalar
    aws --region us-west-2 ec2 describe-instances --filter Name=tag:Cluster,Values=$EC2TAG_CLUSTER --query 'Reservations[].Instances[].[PrivateIpAddress,Tags[?Key==`Name`].Value[]]' --output text | sed '$!N;s/\n/ /' | grep -v '^None' | xargs -n1 -I {} printf "%s  #cloud_init\n" "{}" | tee -a /etc/hosts
fi

