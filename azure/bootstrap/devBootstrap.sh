#!/bin/bash
#
# shellcheck disable=SC2006,SC2155,SC2034,SC2164,SC1091

LOGFILE=startup.log
touch $LOGFILE
chmod 0600 $LOGFILE

exec > >(tee -a $LOGFILE |logger -t user-data -s 2>/dev/console) 2>&1

set -x

echo "Starting bootstrap at `date`"

genDefaultAdmin() {
    local crypted=$(/opt/xcalar/bin/node -e "var crypto=require(\"crypto\"); var hmac=crypto.createHmac(\"sha256\", \"xcalar-salt\").update(\"${ADMIN_PASSWORD}\").digest(\"hex\"); process.stdout.write(hmac+\"\n\")")
    cat <<EOF
{"username": "${ADMIN_USERNAME}", "password": "$crypted", "email": "${ADMIN_EMAIL}", "defaultAdminEnabled": true}
EOF
}

xcalar_version() {
    rpm -q xcalar --qf '%{VERSION}' | sed 's/\./ /g'
}


cat >/etc/hosts<<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF

# API Services
INSTALLER_SERVER="https://zqdkg79rbi.execute-api.us-west-2.amazonaws.com/stable/installer"
LICENSE_SERVER="https://x3xjvoyc6f.execute-api.us-west-2.amazonaws.com/production/license/api/v1.0/marketplacedeploy"

# Static files on Azure Storage
PUBLIC_REPO="https://xcrepo.blob.core.windows.net/public/azuremp/v1"
HTML="${PUBLIC_REPO}/html-4.tar.gz"
CADDY_VERSION="0.11.0-103"
CADDY="${PUBLIC_REPO}/caddy_${CADDY_VERSION}_linux_amd64.gz"

SHARE=""
WEBHOOK=""

# By default use the LetsEncrypt staging server so we don't trigger
# CA limits for this domain
CASTAGING="https://acme-staging.api.letsencrypt.org/directory"
CASERVER="$CASTAGING"

log () {
    logger --id -t $(basename ${BASH_SOURCE[0]}) -s "$@"
}

while getopts "a:b:c:d:e:f:g:i:j:n:l:u:r:p:s:t:v:w:x:y:z:" optarg; do
    case "$optarg" in
        a) SUBDOMAIN="$OPTARG";;
        b) export AWS_HOSTED_ZONE_ID="$OPTARG";;
        c) CLUSTER="$OPTARG";;
        d) DOMAINNAMELABEL="$OPTARG";;
        e) export AWS_ACCESS_KEY_ID="$OPTARG";;
        f) export AWS_SECRET_ACCESS_KEY="$OPTARG";;
        g) PASSWORD="$OPTARG";;
        i) INDEX="$OPTARG";;
        j) export AZURE_STORAGE_SAS_TOKEN="$OPTARG";;
        n) COUNT="$OPTARG";;
        l) LICENSE="$OPTARG";;
        u) INSTALLER_URL="$OPTARG";;
        r) CASERVER="$OPTARG";;
        p) PEM_URL="$OPTARG";;
        t) CONTAINER="$OPTARG";;
        s) SHARE="$OPTARG";;
        v) ADMIN_EMAIL="$OPTARG";;
        w) ADMIN_USERNAME="$OPTARG";;
        x) ADMIN_PASSWORD="$OPTARG";;
        y) export AZURE_STORAGE_ACCOUNT="$OPTARG";;
        z) export AZURE_STORAGE_ACCESS_KEY="$OPTARG"; export AZURE_STORAGE_KEY="$OPTARG";;
        *) echo >&2 "Unknown option $optarg $OPTARG";; # exit 2;;
    esac
done
shift $((OPTIND-1))

CLUSTER="${CLUSTER:-${HOSTNAME%-vm[0-9]*}}"
CONTAINER="${CONTAINER:-$CLUSTER}"
VMBASE="${CLUSTER}-vm"

XLRDIR=/opt/xcalar

# Safer curl. Use IPv4, follow redirects (-L), and add some retries. We've seen curl
# try to use IPv6 on AWS, and many intermittent errors when not retrying. --location
# to follow redirects is pretty much mandatory.
safe_curl () {
    curl -4 --location --retry 20 --retry-delay 3 --retry-max-time 60 "$@"
}

# Removes an entry from fstab
clean_fstab () {
    test -n "$1" && sed -i '\@'$1'@d' /etc/fstab
}

extract () {
    sed -n '/^__TARBALL__/,$p' "$1" | tail -n+2
}

extract_top () {
    sed -n '1,/^__TARBALL__$/p' "$1"
}

# grow_partition [device] [partition#] will grow the partition by
# first removing it, then recreating it to fit the entire device
grow_partition () {
    if command -v growpart >/dev/null 2>&1; then
        growpart "$@"
    else
        cat << EOF | fdisk $1
d
$2

n
p
2


w
EOF
    fi
    # This forces the kernel to rescan the partition
    partx -u ${1}${2}
    if [ "$(blkid -s TYPE -o value ${1}${2})" = xfs ]; then
        xfs_growfs ${1}${2}
    else
        resize2fs ${1}${2}
    fi
}

mount_netstore_nfs() {
    mountpoint -q /netstore && umount /netstore
    mkdir -p /netstore/datasets
    mount -t nfs -o _netdev,defaults netstore:/data/nfs/datasets /netstore/datasets
    mkdir -p /netstore/udf
    mount -t nfs -o _netdev,defaults netstore:/data/nfs/udf /netstore/udf
}

# netstore is a storage container. We use blobfuse to mount it
mount_netstore() {
    safe_curl -sSL https://packages.microsoft.com/config/rhel/7/prod.repo > microsoft-prod.repo
    sed -i 's/gpgcheck=1/gpgcheck=0/g' microsoft-prod.repo
    cp microsoft-prod.repo /etc/yum.repos.d/

    safe_curl -sSL https://packages.microsoft.com/keys/microsoft.asc > microsoft.asc
    rpm --import microsoft.asc

    yum install -y blobfuse
    cat <<EOF > fuse_connection.cfg
accountName xcnetstore
accountKey NiK0kSikzH/727Fg4MFFBGwDbgW7PrFoj50id4g3Go9l/FjYqO6yUiBVjW94Yg5kuDJEUyIlrMRzyXIKugJqhg==
containerName netstore
EOF

    mkdir -p /mnt/ramdisk
    mount -t tmpfs -o size=4g tmpfs /mnt/ramdisk
    mkdir /mnt/ramdisk/blobfusetmp

    mkdir /netstore
    blobfuse /netstore --tmp-path=/mnt/ramdisk/blobfusetmp --config-file=fuse_connection.cfg -o attr_timeout=240 -o entry_timeout=240 -o negative_timeout=120 -o allow_other
}

# mount_device /path /dev/partition will mount the given partition to the path. If
# the partition doesn't exist it is created from the underlying device. If the
# device is already mounted somewhere else, it is unmounted. *CAREFUL* when calling
# this function, it will destroy the specified device.
mount_device () {
    test $# -ge 2 || return 1
    test -n "$1" && test -n "$2" || return 1
    local PART='' MOUNT="$1" PARTIN="$2" DEV="${2%[1-9]}" LABEL="$3" FSTYPE="${4:-ext4}"
    if PART="$(set -o pipefail; findmnt -n $MOUNT | awk '{print $2}')"; then
        local OLDMOUNT="$(findmnt -n $MOUNT | awk '{print $1}')"
        if [ "$PART" != "$PARTIN" ] || [ -z "$OLDMOUNT" ]; then
            echo >&2 "Bad mount $MOUNT on device $PARTIN. Bailing." >&2
            return 1
        fi
        umount $OLDMOUNT
    fi
    # If there's already a partition table, you need to sgdisk it twice
    # because it 'fails' the first time. sgdisk aligns the partition for you
    # -n1 creates an aligned partition using the entire disk, -t1 sets the
    # partition type to 'Linux filesystem' and -c1 sets the label to 'LABEL'
    sgdisk -Zg -n1:0:0 -t1:8300 -c1:$LABEL $DEV || sgdisk -Zg -n1:0:0 -t1:8300 -c1:$LABEL $DEV
    test $? -eq 0 || return 1
    sync
    local retry=
    for retry in $(seq 5); do
        sleep 5
        if [ "$FSTYPE" = xfs ]; then
            time mkfs.xfs -f $PARTIN && break
        elif [ "$FSTYPE" = ext4 ]; then
            # Must use -F[orce] because the partition may have already existed with a valid
            # file system. sgdisk doesn't earase the partitioning information, unlike parted/fdisk.
            # lazy_itable_init=0,lazy_journal_init=0 take too long on Azure
            time mkfs.ext4 -F -m 0 -E discard $PARTIN && break
        fi
    done
    test $? -eq 0 || return 1
    local UUID="$(blkid -s UUID $PARTIN -o value)"
    clean_fstab $UUID && \
    clean_fstab "$MOUNT" && \
    mkdir -p $MOUNT && \
    if [ "$FSTYPE" = xfs ]; then
        echo "UUID=$UUID   $MOUNT      xfs         defaults,discard,relatime,nobarrier,nofail  0   0" | tee -a /etc/fstab
    elif [ "$FSTYPE" = ext4 ]; then
        echo "UUID=$UUID   $MOUNT      ext4        defaults,discard,relatime,nobarrier,nofail  0   0" | tee -a /etc/fstab
    fi
    mount $MOUNT
}

setenforce Permissive
sed -i -e 's/^SELINUX=enforcing.*$/SELINUX=permissive/g' /etc/selinux/config
yum clean all --enablerepo='*'
rm -rf /var/cache/yum/*

# AzureCLI (ref: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo

VERS="$(rpm -q $(rpm -qf /etc/redhat-release) --qf '%{VERSION}')"
VERS="${VERS:0:1}"
if ! rpm -q epel-release; then
    case "$(rpm -qf /etc/redhat-release)" in
        redhat*) EPEL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-${VERS}.noarch.rpm;;
        *) EPEL=epel-release;;
    esac
    yum install -y $EPEL
fi

yum install -y http://repo.xcalar.net/xcalar-release-el${VERS}.rpm

# BEGIN DEBUG
yum install -y --enablerepo='xcalar-deps-common' xcalar-ssh-ca
# END DEBUG

yum install -y nfs-utils parted gdisk curl lvm2 yum-utils cloud-utils-growpart java-1.8.0-openjdk-headless freetds
yum install -y jq python-pip azure-cli htop tmux iperf3 vim-enhanced ansible samba-client samba-common cifs-utils iotop iftop perf

# Microsoft's Network testing tool. See: https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-bandwidth-testing
curl -L -f -o /usr/local/bin/ntttcp https://xcrepo.blob.core.windows.net/public/azuremp/v1/ntttcp && chmod +x /usr/local/bin/ntttcp

setup_instancestore () {
    # Remove waagent's role in managing the disk
    if ! test -b "$1"; then
        log "ERROR: Disk $1 isn't a block device"
        return 1
    fi
    yum install -y --enablerepo='xcalar*' ephemeral-disk

    sed -i '/LV_SWAP_SIZE/d' /etc/sysconfig/ephemeral-disk
    echo "LV_SWAP_SIZE=MEMSIZE2X" >> /etc/sysconfig/ephemeral-disk

    sed -i 's/^ResourceDisk.Format=y/ResourceDisk.Format=n/g' /etc/waagent.conf

    echo "Remove fstab and systemd unit for default /mnt/resource"
    systemctl disable --now mnt-resource.mount
    systemctl mask mnt-resource.mount
    sed -i "/resource/d" /etc/fstab
    # we're creating our own swap partition
    systemctl disable --now temp-disk-swapfile.mount
    systemctl mask temp-disk-swapfile.mount

    DISK="$1"
    INSTANCESTORE=$2
    if test -b "${DISK}1"; then
        if OLDMOUNT=$(set -o pipefail; findmnt -n ${DISK}1 | awk '{print $1}'); then
            local count=1
            while mountpoint -q $OLDMOUNT && [ $count -lt 100 ]; do
                umount $OLDMOUNT && break
                if test -e "$OLDMOUNT/swapfile"; then
                    swapoff "$OLDMOUNT/swapfile"
                    rm -f "$OLDMOUNT/swapfile"
                fi
                log "Waiting to unmount $OLDMOUNT ... ${count}"
                sleep 5
                count=$((count+1))
            done
            sleep 5
        fi
        parted "${DISK}" -s 'rm 1'
        sleep 5
        partx -u "${DISK}"
    fi
    if ephemeral-disk; then
        return 0
    fi
    INSTANCESTORE=''
    DISK=''
    return 1
}

setup_swap() {
    DEVICE="$1"

    parted "$DEVICE" -s 'mklabel gpt'
    parted "$DEVICE" -s 'mkpart primary 1 -1'

    PART="${1}1"

    until test -b $PART; do
        echo "Waiting for $PART to become available..."
        echo "*** lsblk"
        lsblk
        echo "*** blkid"
        blkid
        echo "*** /dev/sd?"
        ls -l /dev/sd*
        echo "*** /dev/disk/azure"
        ls -al /dev/disk/azure/
        echo "***"
        sleep 2
    done
    sleep 2
    mkswap -f $PART

    until UUID=$(blkid $PART -s UUID -o value) && [ -n "$UUID" ]; do
        echo "Waiting for UUID of $PART to become available..."
        sleep 1
    done
    echo "UUID=$UUID	swap	swap	pri=0	0	0" | tee -a /etc/fstab >/dev/null
    swapon -a
    sleep 1
    swapon -a
}

# The root parition is not resized by default on Azure. Handy symlink provided
# in /dev/disk/azure/root (eg, -> /dev/sda) for where we take the 2nd partition
# with the first being the boot partition.
grow_partition $(readlink -f /dev/disk/azure/root) 2

# On Azure the local/spare disks are identified via /dev/disk/azure/resource
# with the first partition being resource-part1. This is similar to how AWS
# does it via /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_AWS*. From
# all indications, Azure only ever comes with one resource disk.
setup_instancestore "$(readlink -f /dev/disk/azure/resource)" /ephemeral/data

serveError() {
    errorMsg="$1"
    rectifyMsg="$2"

    pip install -U jinja2
    test -n "$HTML" && safe_curl -sSL "$HTML" > html.tar.gz
    tar -zxvf html.tar.gz

    cd html
    python ./render.py "$errorMsg" "$rectifyMsg"
    nohup python -m SimpleHTTPServer 80 >> /var/log/xcalarHttp.log 2>&1 &
}

# If INSTALLER_URL is provided, then we don't have to check the license
if [ -z "$INSTALLER_URL" ]; then
    retVal=`safe_curl -H "Content-Type: application/json" -X POST -d "{ \"licenseKey\": \"$LICENSE\", \"numNodes\": $COUNT, \"installerVersion\": \"latest\" }" $INSTALLER_SERVER`
    success=`echo "$retVal" | jq .success`
    if [ "$success" = "false" ]; then
        errorMsg=`echo "$retVal" | jq -r .error`
        echo 2>&1 "ERROR: $errorMsg"
        if [ "$errorMsg" = "License key not found" ]; then
            rectifyMsg="Please contact Xcalar at <a href=\"mailto:sales@xcalar.com\">sales@xcalar.com</a> for a trial license"
        else
            rectifyMsg="Please contact Xcalar support at <a href=\"mailto:support@xcalar.com\">support@xcalar.com</a>"
        fi
        serveError "$errorMsg" "$rectifyMsg"
        exit 1
    fi
    INSTALLER_URL=`echo "$retVal" | jq -r '.signedUrl'`
    WEBHOOK="$LICENSE_SERVER"
fi

# SHARE specifies a full path a cifs share via //server/share, a NFS share via
# server:/share, a local share via /path, or a share name via 'name'
# as the server
if [ -z "$SHARE" ]; then
    if [ -z "$NFSHOST" ] && [ "$COUNT" = 1 ]; then
        SHARE="${HOSTNAME}:/srv/share"
    else
        SHARE="${VMBASE}0:/srv/share"
    fi
    MOUNT_TYPE=nfs
    NFSHOST="${SHARE%%:*}"
    NFSSHARE="${SHARE##*:}"
elif echo "$SHARE" | grep -qE '^(//[a-z][a-z0-9]{2,24}|[a-zA-Z0-9_-]+$)'; then
    MOUNT_TYPE=cifs
elif echo "$SHARE" | grep -qE '^[a-z0-9\.-]*:/[A-Za-z0-9\._-]+'; then
    MOUNT_TYPE=nfs
    NFSHOST="${SHARE%%:*}"
    NFSSHARE="${SHARE##*:}"
elif echo "$SHARE" | grep -qE '^/[a-z_][A-Za-z0-9\._-]+'; then
    MOUNT_TYPE=local
fi

XCE_HOME="${XCE_HOME:-/mnt/xcalar}"
XCE_CONFIG="${XCE_CONFIG:-/etc/xcalar/default.cfg}"
XCE_LICENSEDIR="${XCE_LICENSEDIR:-/etc/xcalar}"

INSTALLER=installer.sh
rm -f $INSTALLER
for retry in $(seq 10); do
    echo >&2 "Downloading $INSTALLER_URL to `pwd`/$INSTALLER"
    if curl -fsSL "$INSTALLER_URL" -o "$INSTALLER" && test -s "$INSTALLER"; then
        rc=0
        break
    fi
    sleep 10
done

if [ $rc -ne 0 ] || ! test -s ${INSTALLER}; then
    echo >&2 "ERROR: Error downloading installer"
    serveError "Error downloading installer"
    exit 1
fi

# Determine our CIDR by querying the metadata service
safe_curl -H Metadata:True "http://169.254.169.254/metadata/instance?api-version=2018-04-02&format=json" | jq . > metadata.json
retCode=${PIPESTATUS[0]}
if [ "$retCode" != "0" ]; then
    echo >&2 "ERROR: Could not contact metadata service"
    serveError "Could not contact metadata service" "Please contact Xcalar support at <a href=\"mailto:support@xcalar.com\">support@xcalar.com</a>"
    exit $retCode
fi

# Convert metadata tags into KEY=value pairs
jq -r .compute.tags < metadata.json  | tr ';' '\n' | sed -r -e 's/^([^:]+):(.*)$/\U\1\E=\2/g' | tee tags.sh
. tags.sh

NETWORK="$(<metadata.json jq -r '.network.interface[].ipv4.subnet[].address')"
MASK="$(<metadata.json jq -r '.network.interface[].ipv4.subnet[].prefix')"
LOCALIPV4="$(<metadata.json jq -r '.network.interface[].ipv4.ipAddress[].privateIpAddress')"
PUBLICIPV4="$(<metadata.json jq -r '.network.interface[].ipv4.ipAddress[].publicIpAddress')"
LOCATION="$(<metadata.json jq -r '.compute.location')"
VMSIZE="$(<metadata.json jq -r '.compute.vmSize')"

# On some Azure instances /mnt/resource comes premounted but not aligned properly
#if ! test -d $INSTANCESTORE; then
#    if ! RESOURCEDEV="$(set -o pipefail; findmnt -n $INSTANCESTORE | awk '{print $2}')"; then
#		if test -b /dev/disk/azure/resource-part1; then
#			RESOURCEDEV=$(readlink -f /dev/disk/azure/resource-part1)
#		elif test -b /dev/disk/azure/resource; then
#			RESOURCEDEV=$(readlink -f /dev/disk/azure/resource)1
#		fi
#	fi
#    mount_device $INSTANCESTORE $RESOURCEDEV SSD ext4
#fi

MEMSIZEMB=$(free -m | awk '/Mem:/{print $2}')
SWAPSIZEMB=$MEMSIZEMB
case "$VMSIZE" in
	Standard_E*) SWAPSIZEMB=$((MEMSIZEMB*2));;
	*) ;;
esac

# Format and mount additional SSD, and prefer to use that
for DEV in /dev/sdc /dev/sdd; do
    if test -b ${DEV} && ! test -b "${DEV}1"; then
        mount_device /mnt/ssd  "${DEV}1" SSD2 xfs
        LOCALSTORE=/mnt/ssd
        break
    fi
done

### Install Xcalar
if [ -s "$INSTALLER" ]; then
    if ! bash -x "$INSTALLER" --nostart; then
        echo >&2 "ERROR: Failed to run installer"
        serveError "Failed to run installer" "Please contact Xcalar support at <a href=\"mailto:support@xcalar.com\">support@xcalar.com</a>"
        exit 1
    fi
fi

# Node 0 will host NFS shared storage for the cluster
if [ "$MOUNT_TYPE" = nfs ]; then
    if [ "$HOSTNAME" = "$NFSHOST" ]; then
        mkdir -p "${LOCALSTORE}/share" "$NFSSHARE"
        clean_fstab "${LOCALSTORE}/share"
        echo "${LOCALSTORE}/share    $NFSSHARE   none   bind   0 0" | tee -a /etc/fstab
        mountpoint -q $NFSSHARE || mount $NFSSHARE
        # Ensure NFS is running
        systemctl enable rpcbind
        systemctl enable nfs-server
        systemctl enable nfs-lock
        systemctl enable nfs-idmap
        systemctl start rpcbind
        systemctl start nfs-server
        systemctl start nfs-lock
        systemctl start nfs-idmap

        # Export the share to everyone in our CIDR block and mark it
        # as world r/w
        mkdir -p "${NFSSHARE}/xcalar"
        chmod 0777 "${NFSSHARE}/xcalar"
        echo "${NFSSHARE}/xcalar      ${NETWORK}/${MASK}(rw,sync,no_root_squash,no_all_squash)" | tee /etc/exports
        systemctl restart nfs-server
        if firewall-cmd --state; then
            firewall-cmd --permanent --zone=public --add-service=nfs
            firewall-cmd --reload
        fi
    else
        mkdir -p /mnt/tmp
        mount -t nfs -o defaults ${NFSHOST}:${NFSSHARE} /mnt/tmp
        mkdir -p /mnt/tmp/cluster/${CLUSTER}
        chown xcalar:xcalar /mnt/tmp/cluster/${CLUSTER}
        umount /mnt/tmp
    fi
fi


# az hangs in telemetry.py occasionally casuing the whole cluster bootup sequence to hang
az_disable_telemetry() {
    local azconfig=${HOME:-/root}/.azure/config
    test -e $(dirname $azconfig) || mkdir -m 0755 -p $(dirname $azconfig)
    if ! test -e $azconfig; then
        printf '[cloud]\nname = AzureCloud\n\n[core]\ncollect_telemetry = no\n\n' > $azconfig
    elif grep -q '\[core\]' $azconfig; then
        sed -i '/collect_telemetry/d' $azconfig
        sed -i 's/\[core\]/\[core\]\ncollect_telemetry = no/g' $azconfig
    else
        printf '\n[core]\ncollect_telemetry = no\n\n' >> $azconfig
    fi
}
az_disable_telemetry
# See: https://docs.microsoft.com/en-us/cli/azure/azure-cli-configuration?view=azure-cli-latest
export AZURE_CORE_COLLECT_TELEMETRY=0

# Returns relative date in az compatible format
# ex: format_expiry "10 days" -> 2017-10-01T1200Z
az_format_expiry () {
    date -u -d "$1" +'%Y-%m-%dT%H:%MZ'
}

# generate an az storage account sas token given an expiry date relative from now (eg, "10 days")
# more info: az storage account generate-sas --help
# quick ref: services -> (b)lob, (f)ile ..
#            resource-types -> (s)ervice, (c)ontainer, (o)bject
#            permissions -> (a)dd, (c)create, ..
az_storage_sas () {
    az storage account generate-sas --services bfqt --resource-types sco --permissions racwdl --expiry $(az_format_expiry "$1") --output tsv
}

az_storage_share_create () {
    local exists created rc
    exists="$(az storage share exists --name $1 ${2:+--account-name $2} -ojson --query 'exists')"
    rc=$?
    if [ $rc -ne 0 ]; then
        return $rc
    fi
    if [ "$exists" = true ]; then
        return 0
    fi

    created="$(az storage share create --name $1 ${2:+--account-name $2} -ojson --query 'created')"
    rc=$?
    if [ $rc -ne 0 ]; then
        return $rc
    fi
    if [ "$created" != true ]; then
        log "Didn't create share"
    else
        log "Created $1 share"
    fi
}

# TODO: Should store this instead of AZURE_*_KEY
if [ -n "$AZURE_STORAGE_KEY" ] && [ -z "$AZURE_STORAGE_SAS_TOKEN" ]; then
    export AZURE_STORAGE_SAS_TOKEN="$(az_storage_sas '365 days')"
fi

if test -n "$AZURE_STORAGE_SAS_TOKEN" && touch /etc/azure; then
    # Only allow access by root
    chmod 0600 /etc/azure
    echo "## Azure Blob Storage config" >> /etc/azure
    echo "AZURE_STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT" >> /etc/azure
    test -n "$AZURE_STORAGE_ACCESS_KEY" && echo "AZURE_STORAGE_ACCESS_KEY=$AZURE_STORAGE_ACCESS_KEY" >> /etc/azure
    test -n "$AZURE_STORAGE_KEY" && echo "AZURE_STORAGE_KEY=$AZURE_STORAGE_KEY" >> /etc/azure
    echo "AZURE_STORAGE_SAS_TOKEN=\"$AZURE_STORAGE_SAS_TOKEN\"" >> /etc/azure
    if [ -r /etc/default/xcalar ]; then
        cat /etc/azure >> /etc/default/xcalar
        echo "export AZURE_STORAGE_ACCOUNT AZURE_STORAGE_ACCESS_KEY AZURE_STORAGE_KEY AZURE_STORAGE_SAS_TOKEN" >> /etc/default/xcalar
        # should filter out _KEY and only keep ACCOUNT_NAME and SAS_TOKEN in
        # /etc/default/xcalar. Since this file contains secrets, remove world
        # readable bit.
        chmod 0660 /etc/default/xcalar
        # In addition, give xcalar group the read permissions so that any
        # xcalarctl calls run as xcalar user can source the default file.
        chgrp xcalar /etc/default/xcalar
        . /etc/default/xcalar
    else
        . /etc/azure
        export AZURE_STORAGE_ACCOUNT AZURE_STORAGE_ACCESS_KEY AZURE_STORAGE_KEY AZURE_STORAGE_SAS_TOKEN
    fi
fi

# Only have head node create the container
if [ "$INDEX" = 0 ] && [ -n "$CONTAINER" ]; then
    # Don't strictly need to pass the account name and sas token as they're in env vars, just here
    # for reference should we decide to remove the global env vars
    CONTAINER_CREATED=$(az storage container create --account-name "$AZURE_STORAGE_ACCOUNT" --sas-token "$AZURE_STORAGE_SAS_TOKEN" --name $CONTAINER --query 'created')
    if [ "$CONTAINER_CREATED" = true ]; then
        echo "Created container $CONTAINER"
    else
        echo "Failed to create container $CONTAINER"
    fi
fi


# Generate a list of all cluster members
DOMAIN="$(dnsdomainname)"
MEMBERS=()
for ii in $(seq 0 $((COUNT-1))); do
    MEMBERS+=("${VMBASE}${ii}.${DOMAIN}")
done

# Register domain
CNAME="${DOMAINNAMELABEL}.${LOCATION}.cloudapp.azure.com"
if [ -z "$SUBDOMAIN" ]; then
    SUBDOMAIN="${LOCATION}.cloudapp.azure.com"
fi

DEPLOYED_URL=""
XCE_DNS=""
cp -n /etc/xcalar/Caddyfile /etc/xcalar/Caddyfile.orig
if [ "$PUBLICIPV4" != "" ]; then
    if [ "$INDEX" = 0 ]; then
        XCE_DNS="${DOMAINNAMELABEL}.${SUBDOMAIN}"
    fi
    if [ -z "$XCE_DNS" ]; then
        XCE_DNS="${DOMAINNAMELABEL}${INDEX}.${SUBDOMAIN}"
    fi
    (
    echo ":443, https://${XCE_DNS}:443 {"
    tail -n+2 /etc/xcalar/Caddyfile
    echo ":80, http://${XCE_DNS} {"
    echo "  redir https://{host}{uri}"
    echo "}"
    ) | tee /etc/xcalar/Caddyfile.$$
    mv /etc/xcalar/Caddyfile.$$ /etc/xcalar/Caddyfile
    if [ "$INDEX" = 0 ] && test -e "/etc/xcalar/${XCE_DNS}.key"; then
        sed -i -e "s|tls.*$|tls /etc/xcalar/${XCE_DNS}.crt /etc/xcalar/${XCE_DNS}.key|g" /etc/xcalar/Caddyfile
    else
        sed -i -e 's/tls.*$/tls self_signed/g' /etc/xcalar/Caddyfile
    fi
    DEPLOYED_URL="https://$XCE_DNS"
else
    (
    echo ":443 {"
    tail -n+2 /etc/xcalar/Caddyfile.orig
    echo ":80 {"
    echo "  redir https://{host}{uri}"
    echo "}"
    ) | sed -e 's/tls.*$/tls self_signed/g' | tee /etc/xcalar/Caddyfile.$$
    mv /etc/xcalar/Caddyfile.$$ /etc/xcalar/Caddyfile
fi

# Custom SerDes path on local storage
if [ -n "$INSTANCESTORE" ]; then
    XCE_XDBSERDESPATH="${INSTANCESTORE}/serdes"
    mkdir -m 0755 -p $XCE_XDBSERDESPATH
    chown xcalar:xcalar $XCE_XDBSERDESPATH
fi
# Generate /etc/xcalar/default.cfg
(
if [ $COUNT -eq 1 ]; then
    ${XLRDIR}/scripts/genConfig.sh /etc/xcalar/template.cfg - localhost
else
    ${XLRDIR}/scripts/genConfig.sh /etc/xcalar/template.cfg - "${MEMBERS[@]}"
fi | sed '/^Constants.XcalarRootCompletePath=/d'

# Custom XcalarRoot
echo Constants.XcalarRootCompletePath=$XCE_HOME

# Enable ASUP on Cloud deployments
echo Constants.SendSupportBundle=true

# echo "Constants.Cgroups=$CGROUPS_ENABLED"

if [ -n "$XCE_XDBSERDESPATH" ]; then
    # 2.0.4 specific fix
    version=($(xcalar_version))
    if [ ${version[0]} -eq 2 ] && [ ${version[1]} -lt 2 ] && [ ${version[2]} -ge 4 ]; then
        echo Constants.BufCacheNonTmpFs=true
        echo Constants.BufferCachePath=$XCE_XDBSERDESPATH
    fi
    echo Constants.XdbSerDesMode=2
    echo Constants.XdbLocalSerDesPath=$XCE_XDBSERDESPATH
    echo Constants.XdbSerDesMaxDiskMB=0
    echo Constants.EnforceVALimit=false
fi
) | tee "$XCE_CONFIG"

if [ -n "$LICENSE" ]; then
    LIC="$(mktemp --tmpdir license.XXXXXX)"
    if echo -n "$LICENSE" | base64 -d | gzip -dc > $LIC; then
        echo >&2 "Decompressed license"
    else
        echo -n "$LICENSE" > $LIC
    fi
    mv $LIC "${XCE_LICENSEDIR}/XcalarLic.key"
    chmod 0640 "${XCE_LICENSEDIR}/XcalarLic.key"
fi

# Make Xcalar config dir writable by xcalar user for config changes via XD
chown -R xcalar:xcalar /etc/xcalar

# Set up the mount for XcalarRoot
mkdir -p "$XCE_HOME"
clean_fstab $XCE_HOME
case "$MOUNT_TYPE" in
    nfs)
        MOUNT_OPTS='_netdev,defaults'
        MOUNT_WHAT="${NFSHOST}:${NFSSHARE}/cluster/${CLUSTER}"
        ;;
    cifs)
        mkdir -p /etc/credentials.d
        chmod 0700 /etc/credentials.d
        CREDENTIALS=/etc/credentials.d/${AZURE_STORAGE_ACCOUNT}
        rm -f $CREDENTIALS
        touch $CREDENTIALS
        chmod 0600 $CREDENTIALS
        echo "username=${AZURE_STORAGE_ACCOUNT}" >> $CREDENTIALS
        echo "password=${AZURE_STORAGE_KEY}" >> $CREDENTIALS
        MOUNT_OPTS="_netdev,vers=2.1,sec=ntlmssp,credentials=$CREDENTIALS,file_mode=0600,dir_mode=0775,uid=xcalar,gid=xcalar,serverino,mapposix,rsize=1048576,wsize=1048576,echo_interval=60"
        MOUNT_WHAT="//${AZURE_STORAGE_ACCOUNT}.file.core.windows.net/${SHARE}"
        az_storage_share_create "$SHARE"
        ;;
    local)
        chown xcalar:xcalar "$XCE_HOME"
        ;;
esac

if [ "$MOUNT_TYPE" != local ]; then
    mkdir -p $XCE_HOME
    echo "$MOUNT_WHAT   $XCE_HOME   $MOUNT_TYPE     $MOUNT_OPTS     0   0" | tee -a /etc/fstab
    mount $XCE_HOME
    chown -R xcalar:xcalar  $XCE_HOME


#    cat > /etc/systemd/system/mnt-xcalar.mount <<-EOF
#	[Unit]
#	Description=Xcalar Shared Root
#	Requires=network-online.target
#	After=network-online.service
#	[Mount]
#	What=$MOUNT_WHAT
#	Where=$XCE_HOME
#	SloppyOptions=on
#	DirectoryMode=0755
#	Type=$MOUNT_TYPE
#	Options=$MOUNT_OPTS
#	[Install]
#	WantedBy=remote-fs.target
#	EOF
#    systemctl daemon-reload
#    systemctl enable mnt-xcalar.automount
#    systemctl start mnt-xcalar.automount
    ls $XCE_HOME  # Force mount of shared dir
    # Wait for share to fully come up. Often times the other nodes get to this point before node0 has
    # even begun
    until mountpoint -q "$XCE_HOME"; do
        echo >&2 "Sleeping ... waiting $XCE_HOME"
        sleep 5
    done
    chown -R xcalar:xcalar "$XCE_HOME"
fi

until mkdir -p "${XCE_HOME}/members"; do
    echo >&2 "Sleeping ... waiting $XCE_HOME/members"
    sleep 5
done

echo "$LOCALIPV4        $(hostname -f)  $(hostname -s) vm${INDEX}" > "${XCE_HOME}/members/${INDEX}"
while :; do
    COUNT_ONLINE=$(find "${XCE_HOME}/members/" -type f | wc -l)
    echo >&2 "Have ${COUNT_ONLINE}/${COUNT} nodes online"
    if [ $COUNT_ONLINE -eq $COUNT ]; then
        break
    fi
    echo >&2 "Sleeping ... waiting for nodes"
    sleep 5
done
chown xcalar:xcalar "$XCE_HOME"

# Populate the local host keys with those of the members so we can SSH into them without
# the hostkey check warning
# shellcheck disable=SC2162
cat ${XCE_HOME}/members/* | while read HOSTENTRY; do
    echo "$HOSTENTRY" | tee -a /etc/hosts >/dev/null
    ssh-keyscan $HOSTENTRY
done | tee /etc/ssh/ssh_known_hosts
ssh-keyscan localhost | tee -a /etc/ssh/ssh_known_hosts

# Add the hosts to ansible
cat ${XCE_HOME}/members/* | awk '{print $(NF)}' | tee /etc/ansible/hosts

# Let's mount netstore
if ! mount_netstore_nfs; then
    # If nfs didn't work, use blobstore
    mount_netstore
fi

# Add in the default admin user into Xcalar
if [ -n "$ADMIN_USERNAME" ]; then
    mkdir -p $XCE_HOME/config
    chmod 0700 $XCE_HOME/config
    genDefaultAdmin > $XCE_HOME/config/defaultAdmin.json
    chmod 0600 $XCE_HOME/config/defaultAdmin.json
    chown -R xcalar:xcalar $XCE_HOME/config /etc/xcalar
    ## Doesn't seem to work anymore
    jsonData="{ \"defaultAdminEnabled\": true, \"username\": \"$ADMIN_USERNAME\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\" }"
    echo "Creating default admin user $ADMIN_USERNAME ($ADMIN_EMAIL)"
    # Don't fail the deploy if this curl doesn't work
    safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "http://127.0.0.1:12124/login/defaultAdmin/setup" || true
    echo
else
    echo "ADMIN_USERNAME is not specified"
fi

DROPIN=/etc/systemd/system/xcalar.service.d
mkdir -p $DROPIN
cat > ${DROPIN}/ephemeral.conf <<EOF
[Unit]
After=ephemeral-disk.service
EOF

systemctl daemon-reload
if systemctl cat xcalar.service | grep -q xcalar-caddy.service; then
    systemctl enable --now xcalar.service
else
    systemctl enable --now xcalar-usrnode.service
fi

rc=$?

if [ -n "$DEPLOYED_URL" ] && [ -n "$WEBHOOK" ]; then
    # Inform license server about URL
    jsonData="{ \"key\": \"$LICENSE\", \"url\": \"$DEPLOYED_URL\", \"marketplaceName\": \"Internal Deployment\" }"
    safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "$WEBHOOK"
    echo
fi
echo "DONE ($rc)"
exit $rc
__TARBALL__
