#!/bin/bash

set -ex

env


cloud_id() {
    local dmi_id='/sys/class/dmi/id/sys_vendor'
    local vendor cloud=

    if [ -e "$dmi_id" ]; then
        read -r vendor < "$dmi_id"
        case "$vendor" in
            Microsoft\ Corporation) cloud=azure;;
            Amazon\ EC2) cloud=aws;;
            Google) cloud=gce;;
            #VMWare*) cloud=vmware;;
            #oVirt*) cloud=ovirt;;
        esac
    fi
    echo "$cloud"
}

imds() {
    if [ -z "${IMDSV2_TOKEN}" ]; then
        export IMDSV2_TOKEN=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    fi
    curl -fsS -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/${1#/}"
}

get_meta_data() {
    if [ -n "$CLOUD" ]; then
        case "$CLOUD" in
            aws) imds "$1";;
            gce) curl -H "Metadata-Flavor:Google" -f -sL "http://169.254.169.254/$1";;
            azure) curl -H 'Metadata:True' -f -sL "http://169.254.169.254/metadata/instance/$1?api-version=2018-02-01&format=text";;
        esac
        return $?
    fi
    local http_code=
    http_code="$(curl -H "Metadata-Flavor:Google" -f -sL "http://169.254.169.254/$1" -w '%{http_code}\n' -o /dev/null)"
    if [ "$http_code" = 200 ]; then
        curl -H "Metadata-Flavor:Google" -f -sL "http://169.254.169.254/$1" && return 0
        return 2
    elif curl -H 'Metadata:True' -f -sL "http://169.254.169.254/metadata/instance/$1?api-version=2018-02-01&format=text"; then
        return 0
    fi
    return 1
}

get_cloud_cfg() {
    # Check for metadata service
    CLOUD='' INSTANCE_ID='' INSTANCE_TYPE=''
    CLOUD=$(cloud_id)
    case "$CLOUD" in
        aws)
            INSTANCE_ID="$(imds latest/meta-data/instance-id)";
            INSTANCE_TYPE="$(imds latest/meta-data/instance-type)"
            ;;
        gce)
            INSTANCE_ID="$(get_meta_data computeMetadata/v1/instance/id)"
            INSTANCE_TYPE="$(get_meta_data computeMetadata/v1/instance/machine-type)"
            INSTANCE_TYPE="${INSTANCE_TYPE##*/}"
            ;;
        azure)
            INSTANCE_ID="$(get_meta_data compute/vmId)"
            INSTANCE_TYPE="$(get_meta_data compute/vmSize)"
            ;;
        *)
            CLOUD= INSTANCE_ID= INSTANCE_TYPE=
            ;;
    esac
    echo CLOUD=$CLOUD
    echo INSTANCE_ID=$INSTANCE_ID
    echo INSTANCE_TYPE=$INSTANCE_TYPE
}

keep_trying() {
    local -i try=0
    for try in {1..20}; do
        if eval "$@"; then
            return 0
        fi
        echo "Failed to $* .. sleeping"
        sleep 10
        try=$((try + 1))
        if [ $try -gt 20 ]; then
            return 1
        fi
    done
    return 0
}

curl -fsSL http:/repo.xcalar.net/scripts/osid-201904 -o /usr/bin/osid
chmod +x /usr/bin/osid
OSID=${OSID:-$(osid)}

if test -e /etc/system-release; then
    if test -f /etc/selinux/config; then
        setenforce 0 || true
        sed -i 's/^SELINUX=.*$/SELINUX=disabled/g' /etc/selinux/config
    fi
    yum clean all --enablerepo='*'
    rm -rf /var/cache/yum/*
    yum remove -y java java-1.7.0-openjdk || true
    keep_trying yum update -y
    keep_trying yum localinstall -y http://repo.xcalar.net/xcalar-release-${OSID}.rpm
    yum install -y -q --enablerepo='xcalar-*' nfs-utils xfsprogs sudo lvm2 mdadm btrfs-progs yum-utils fuse tmux bcache-tools || true
else
    export DEBIAN_FRONTEND=noninteractive
    #VERSION_CODENAME=bionic
    (
    . /etc/os-release
    curl -L -O https://google.storageapis.com/repo.xcalar.net/xcalar-release-${VERSION_CODENAME}.deb
    dpkg -i xcalar-release-${VERSION_CODENAME}.deb
    rm xcalar-release-${VERSION_CODENAME}.deb
    )
    keep_trying apt-get update -q
    apt-get -yqq install curl lvm2 xfsprogs bonnie++ bwm-ng mdadm btrfs-tools
    apt-get -yqq dist-upgrade
    apt-get -yqq autoremove
fi

eval $(get_cloud_cfg)

if [ "$CLOUD" = gce ]; then
    if [[ -e /etc/redhat-release ]]; then
        yum localinstall -y http://repo.xcalar.net/deps/gce-scripts-1.3.2-1.noarch.rpm
        yum localinstall -y http://repo.xcalar.net/deps/gcsfuse-0.20.1-1.x86_64.rpm
    fi
elif [ "$CLOUD" = aws ]; then
    yum install -y --enablerepo='xcalar*' ephemeral-disk
    ephemeral-disk
    if ! command -v ec2-tags; then
        curl -fsSL http://repo.xcalar.net/deps/ec2-tags-v3 > /usr/local/bin/ec2-tags-v3
        chmod +x /usr/local/bin/ec2-tags-v3
        ln -sfn ec2-tags-v3 /usr/local/bin/ec2-tags
    fi
elif [ "$CLOUD" = azure ]; then
    yum install -y --enablerepo='xcalar*' ephemeral-disk
    ephemeral-disk
fi

getent group docker || groupadd -f -r -o -g 999 docker
getent group sudo || groupadd -f -r sudo
echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-sudo && chmod 0440 /etc/sudoers.d/99-sudo

if test -n "$BUILD_CONTEXT"; then
    curl -sSL "$BUILD_CONTEXT" | tar zxvf -
fi
