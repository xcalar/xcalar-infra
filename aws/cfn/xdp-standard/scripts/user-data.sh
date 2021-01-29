#!/bin/bash

echo >&2 "Starting user-data.sh"

set -x
LOGFILE=/var/log/user-data.log
touch $LOGFILE
chmod 0600 $LOGFILE
if [ -t 1 ]; then
    :
else
    exec > >(tee -a $LOGFILE | logger -t user-data -s 2> /dev/console) 2>&1
fi

ec2_find_cluster() {
    aws ec2 describe-instances \
        --filters Name=tag:$1,Values=$2 Name=instance-state-name,Values=running \
        --query "Reservations[].Instances[].[AmiLaunchIndex,${3:-PrivateIpAddress}]" \
        --output text | sort -n | awk '{print $2}'
}

eval $(ec2-tags -s -i)

BOOTSTRAP_EXPECT=1

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        --nfs-mount)
            NFSMOUNT="$1"
            shift
            ;;
        --nfs-type)
            NFS_TYPE="$1"
            shift
            ;;
        --nfs-opts)
            NFS_OPTS="$1"
            shift
            ;;
        --tag-key)
            TAG_KEY="$1"
            shift
            ;;
        --tag-value)
            TAG_VALUE="$1"
            shift
            ;;
        --s3bucket)
            S3BUCKET="$1"
            shift
            ;;
        --s3prefix)
            S3PREFIX="$1"
            shift
            ;;
        --bootstrap-expect)
            BOOTSTRAP_EXPECT="$1"
            shift
            ;;
        --license)
            test -z "$1" || LICENSE="$1"
            shift
            ;;
        --installer-url)
            test -z "$1" || INSTALLER_URL="$1"
            shift
            ;;
        --stack-name)
            STACK_NAME="$1"
            shift
            ;;
        --resource-id)
            RESOURCE_ID="$1"
            shift
            ;;
        --admin-username)
            ADMIN_USERNAME="$1"
            shift
            ;;
        --admin-password)
            ADMIN_PASSWORD="$1"
            shift
            ;;
        --admin-email)
            ADMIN_EMAIL="$1"
            shift
            ;;
        *)
            echo >&2 "WARNING: Unknown command $cmd"
            ;;
    esac
done

RELEASE_NAME=$(rpm -qf /etc/system-release --qf '%{NAME}')
RELEASE_VERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
case "$RELEASE_VERSION" in
    6 | 6*) OSID=el6 ;;
    7 | 7*) OSID=el7 ;;
    2018*) OSID=amzn1 ;;
    2) OSID=amzn2 ;;
    *)
        echo >&2 "ERROR: Unknown OS version $RELEASE_VERSION"
        exit 1
        ;;
esac

INSTANCE_ID=$(curl -sSf http://169.254.169.254/latest/meta-data/instance-id)
AVZONE=$(curl -sSf http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_TYPE=$(curl -sSf http://169.254.169.254/latest/meta-data/instance-type)
export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin:/opt/mssql-tools/bin:/opt/xcalar/bin
echo "export PATH=$PATH" > /etc/profile.d/path.sh

set +e
if [ -e /etc/ec2.env ]; then
    set -a
    . /etc/ec2.env
    set +a
fi

if [ -z "$NFSMOUNT" ]; then
    case "$AWS_DEFAULT_REGION" in
        us-east-1) NFSMOUNT=fs-7803cc30:/ ;;
        us-west-2) NFSMOUNT=fs-d4d4237d:/ ;;
        *)
            echo >&2 "Region ${AWS_DEFAULT_REGION} is not supported properly!"
            exit 1
            ;;
    esac
fi

NFSHOST="${NFSMOUNT%%:*}"
NFSDIR="${NFSMOUNT#$NFSHOST}"
NFSDIR="${NFSDIR#:}"
NFSDIR="${NFSDIR#/}"

if [ -z "$NFS_TYPE" ]; then
    if [[ $NFSHOST =~ ^fs-[0-9a-f]{8}$ ]]; then
        rpm -q amazon-efs-utils || yum install -y amazon-efs-utils
        NFS_TYPE=efs
        NFS_OPTS="_netdev"
    else
        NFS_TYPE=nfs
        NFS_OPTS="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
    fi
fi

if ! rpm -q xcalar; then
    yum clean all --enablerepo='*'
    yum install -y unzip yum-utils epel-release patch
    yum install -y http://repo.xcalar.net/xcalar-release-${OSID}.rpm
    yum install -y jq amazon-efs-utils

    mkdir -p -m 0700 /var/lib/xcalar-installer
    cd /var/lib/xcalar-installer

    curl -L "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o awscli-bundle.zip && unzip awscli-bundle.zip && ./awscli-bundle/install -i /opt/aws -b /usr/local/bin/aws
    yum install -y https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.amzn1.noarch.rpm
    yum install -y ephemeral-disk ec2tools --enablerepo='xcalar-*'

    if rpm -q java-1.7.0-openjdk > /dev/null 2>&1; then
        yum remove -y java-1.7.0-openjdk || true
    fi

    sed -i -r 's/^(G|U)ID_MIN.*$/\1ID_MIN            1000/g' /etc/login.defs

    if test -e installer.sh; then
        mv installer.sh installer.sh.$$
    fi
    if [[ $INSTALLER_URL =~ ^http ]]; then
        curl -fL "$INSTALLER_URL" -o installer.sh
    elif [[ $INSTALLER_URL =~ s3:// ]]; then
        aws s3 cp "$INSTALLER_URL" installer.sh
    fi
    if [ $? -eq 0 ] && test -s installer.sh; then
        export ACCEPT_EULA=Y
        chmod 0700 installer.sh
        ./installer.sh --nostart 2>&1 | tee -a installer.log
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            echo "Failed to install ${PWD}/installer.sh (from $INSTALLER_URL)"
            exit 1
        fi
    fi
fi

if [ -n "$LICENSE" ]; then
    if [[ $LICENSE =~ ^s3:// ]]; then
        aws s3 cp $LICENSE - | base64 -d | gzip -dc > /etc/xcalar/XcalarLic.key
    else
        echo "$LICENSE" | base64 -d | gzip -dc > /etc/xcalar/XcalarLic.key
    fi
fi

touch /etc/xcalar/XcalarLic.key
chown xcalar:xcalar /etc/xcalar/XcalarLic.key

# $1 = server:/path/to/share
# $2 = /mnt/localpath
mount_xlrroot() {
    local NFSHOST="${1%%:*}"
    local NFSDIR="${1#$NFSHOST}"
    local MOUNT="$2"

    NFSDIR="${NFSDIR#:}"
    NFSDIR="${NFSDIR#/}"

    local tmpdir=$(mktemp -d -t nfs.XXXXXX)
    set +e
    mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=3 $NFSHOST:/$NFSDIR $tmpdir
    local rc=$?
    if [ $rc -eq 32 ]; then
        mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=3 $NFSHOST:/ $tmpdir
        rc=$?
        if [ $rc -eq 0 ]; then
            mkdir -m 0700 -p ${tmpdir}/${NFSDIR}/members
            chmod 0700 ${tmpdir}/${NFSDIR}
            chown xcalar:xcalar ${tmpdir}/${NFSDIR} ${tmpdir}/${NFSDIR}/members
            umount ${tmpdir}
        fi
    fi
    if mountpoint -q $tmpdir; then
        umount $tmpdir || true
    fi
    rmdir $tmpdir || true

    if [ $rc -eq 0 ]; then
        sed -i '\@'$MOUNT'@d' /etc/fstab
        echo "${NFSHOST}:/${NFSDIR} $MOUNT $NFS_TYPE  $NFS_OPTS 0 0" >> /etc/fstab
        test -d $MOUNT || mkdir -p $MOUNT
        mountpoint -q $MOUNT || mount $MOUNT
        rc=$?
    fi
    return $rc
}

if [ -n "$CLUSTERNAME" ]; then
    TAG_KEY=ClusterName
    TAG_VALUE=$CLUSTERNAME
elif [ -n "$AWS_CLOUDFORMATION_STACK_NAME" ]; then
    TAG_KEY=aws:cloudformation:stack-name
    TAG_VALUE=$AWS_CLOUDFORMATION_STACK_NAME
elif [ -n "$NAME" ]; then
    TAG_KEY=Name
    TAG_VALUE=$NAME
else
    echo >&2 "No valid tags found"
fi

if [ -n "$TAG_VALUE" ]; then
    CLUSTER_ID=$TAG_VALUE
    IPS=()
    while [ "${#IPS[@]}" -eq 0 ]; do
        if IPS=($(ec2_find_cluster $TAG_KEY $TAG_VALUE)); then
            break
        fi
        sleep 2
    done
    sleep 5
else
    CLUSTER_ID="xcalar-$(uuidgen)"
    IPS=(localhost)
fi
NUM_INSTANCES="${#IPS[@]}"

MOUNT_OK=false
XLRROOT=/var/opt/xcalar
if [ -n "$NFSMOUNT" ]; then
    mkdir -p /mnt/xcalar
    if mount_xlrroot $NFSHOST:/${NFSDIR:-cluster/$CLUSTER_ID} /mnt/xcalar; then
        MOUNT_OK=true
        XLRROOT=/mnt/xcalar
    fi
fi

if [ "$MOUNT_OK" = true ]; then
    if ! test -d ${XLRROOT}/jupyterNotebooks; then
        rsync -avzr /var/opt/xcalar/ ${XLRROOT}/
    fi
    /opt/xcalar/scripts/genConfig.sh /etc/xcalar/template.cfg - ${IPS[@]} | sed 's@^Constants.XcalarRootCompletePath=.*$@Constants.XcalarRootCompletePath='${XLRROOT}'@g' | tee /etc/xcalar/default.cfg
else
    XLRROOT=/var/opt/xcalar
    mkdir -p $XLRROOT
    chown xcalar:xcalar $XLRROOT
    /opt/xcalar/scripts/genConfig.sh /etc/xcalar/template.cfg - localhost | tee /etc/xcalar/default.cfg
fi

mkdir -m 0700 -p $XLRROOT/config

if test -x /opt/xcalar/scripts/genDefaultAdmin.sh; then
    /opt/xcalar/scripts/genDefaultAdmin.sh \
        --username "${ADMIN_USERNAME:-xdpadmin}" \
        --email "${ADMIN_EMAIL:-info@xcalar.com}" \
        --password "${ADMIN_PASSWORD:-Welcome1}" > $XLRROOT/config/defaultAdmin.json.tmp \
        && mv $XLRROOT/config/defaultAdmin.json.tmp $XLRROOT/config/defaultAdmin.json
fi

chmod 0700 $XLRROOT/config
chmod 0600 $XLRROOT/config/defaultAdmin.json
chown -R xcalar:xcalar $XLRROOT

EPHEMERAL=/ephemeral/data

if test -x /usr/bin/ephemeral-disk && ! mountpoint -q $EPHEMERAL; then
    ephemeral-disk || true
fi

if test -w $EPHEMERAL; then
    chmod 0777 $EPHEMERAL
fi

enable_serdes() {
    XCE_XDBSERDESPATH="$1"
    XCE_SERDESMODE="$2"
    if [ -n "$XCE_XDBSERDESPATH" ]; then
        XCE_SERDESMODE=${XCE_SERDESMODE:-1}
        XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
        sed -i '/^Constants.XdbLocalSerDesPath=/d' $XCE_CONFIG
        echo "Constants.XdbLocalSerDesPath=${XCE_XDBSERDESPATH%/}/" >> $XCE_CONFIG
        echo "Constants.XdbSerDesMode=$XCE_SERDESMODE" >> $XCE_CONFIG
    fi
}

enable_tags() {
    # You can add and Constants.Foo tag to the instance to have it populate in the config
    # eg, Constants.Cgroup=false
    ec2-tags -t | awk '/^Constants\./{printf "%s=%s\n",$1,$2}' >> $XCE_CONFIG
}

/etc/init.d/xcalar start
rc=$?

chkconfig xcalar on

echo >&2 "All done with user-data.sh (rc=$rc)"
exit $rc
