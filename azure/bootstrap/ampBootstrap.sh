#!/bin/bash
#
# shellcheck disable=SC2086

LOGFILE=startup.log
touch $LOGFILE
chmod 0600 $LOGFILE

exec > >(tee -a $LOGFILE |logger -t user-data -s 2>/dev/console) 2>&1

set -x

echo "Starting bootstrap at `date`"

# API Services
INSTALLER_SERVER="https://zqdkg79rbi.execute-api.us-west-2.amazonaws.com/stable/installer"
LICENSE_SERVER="https://x3xjvoyc6f.execute-api.us-west-2.amazonaws.com/production/license/api/v1.0/marketplacedeploy"

# Static files on Azure Storage
PUBLIC_REPO="https://xcrepo.blob.core.windows.net/public/azuremp/v1"
HTML="${PUBLIC_REPO}/html-4.tar.gz"
XCALAR_ADVENTURE_DATASET="${PUBLIC_REPO}/xcalarAdventure.tar.gz"
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
        --) break;;
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

# mount_device /path /dev/partition will mount the given partition to the path. If
# the partition doesn't exist it is created from the underlying device. If the
# device is already mounted somewhere else, it is unmounted. *CAREFUL* when calling
# this function, it will destroy the specified device.
mount_device () {
    test $# -ge 2 || return 1
    test -n "$1" && test -n "$2" || return 1
    local PART= MOUNT="$1" PARTIN="$2" DEV="${2%[1-9]}" LABEL="$3" FSTYPE="${4:-ext4}"
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
            time mkfs.ext4 -F -m 0 -E nodiscard $PARTIN && break
        fi
    done
    test $? -eq 0 || return 1
    local UUID="$(blkid -s UUID $PARTIN -o value)"
    clean_fstab $UUID && \
    clean_fstab "$MOUNT"  && \
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
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-${VERS}.noarch.rpm
fi

yum install -y http://repo.xcalar.net/xcalar-release-el${VERS}.rpm

# BEGIN DEBUG
yum install -y --enablerepo='xcalar*' xcalar-ssh-ca optgdb8
ln -sfn /opt/gdb8/bin/gdb /usr/local/bin/
# END DEBUG

yum install -y nfs-utils parted gdisk curl lvm2 yum-utils cloud-utils-growpart java-1.8.0-openjdk-headless freetds
yum install -y jq python-pip awscli azure-cli sshpass htop tmux iperf3 vim-enhanced ansible samba-client samba-common cifs-utils iotop iftop perf

run_playload () {
    #(set -o pipefail; extract "${BASH_SOURCE[0]}" | base64 -d | tar zxf - && cd payload && ./install.sh $INSTANCESTORE $DISK)
    test -e payload.tar.gz && tar zxf payload.tar.gz
    (test -d payload && cd payload && ./install.sh $INSTANCESTORE $DISK)
}

setup_instancestore () {
    # Remove waagent's role in managing the disk
    if ! test -b "$1"; then
        log "ERROR: Disk $1 isn't a block device"
        return 1
    fi
    sed -i 's/^ResourceDisk.Format=y/ResourceDisk.Format=n/g' /etc/waagent.conf
    DISK="$1"
    INSTANCESTORE=$2
    yum install --enablerepo='xcalar-deps*' -y ephemeral-disk
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

export TMPDIR=/ephemeral/data/tmp
mkdir -m 1777 $TMPDIR

pip install -U jinja2
test -n "$HTML" && safe_curl -sSL "$HTML" > html.tar.gz
tar -zxvf html.tar.gz

serveError() {
    errorMsg="$1"
    rectifyMsg="$2"
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
if echo "$SHARE" | grep -qE '^(//[a-z][a-z0-9]{2,24}|[a-zA-Z][a-zA-Z0-9_-]+$)'; then
    MOUNT_TYPE=cifs
elif echo "$SHARE" | grep -qE '^[a-z][a-z0-9\.-]*:/[A-Za-z][A-Za-z0-9\._-]+'; then
    MOUNT_TYPE=nfs
    NFSHOST="${SHARE%%:*}"
    NFSSHARE="${SHARE##*:}"
elif echo "$SHARE" | grep -qE '^/[a-z_][A-Za-z0-9\._-]+'; then
    MOUNT_TYPE=local
fi

#if [ -z "$NFSHOST" ] && [ "$COUNT" = 1 ]; then
#    SHARE="${HOSTNAME}:/srv/share"
#else
#    SHARE="${CLUSTER}0:/srv/share"
#fi

#NFSHOST="${SHARE%%:*}"
#SHARE="${SHARE##*:}"

XCE_HOME="${XCE_HOME:-/mnt/xcalar}"
XCE_CONFIG="${XCE_CONFIG:-/etc/xcalar/default.cfg}"
XCE_LICENSEDIR="${XCE_LICENSEDIR:-/etc/xcalar}"

# Download the installer as soon as we can
rm -f installer.sh
for retry in $(seq 10); do
    safe_curl "$INSTALLER_URL" -o installer.sh
    rc=$?
    if [ $rc -eq 0 ] && test -s installer.sh; then
        break
    fi
    sleep 10
done

if [ $rc -ne 0 ] || ! test -s installer.sh; then
    echo >&2 "ERROR: Error downloading installer"
    serveError "Error downloading installer"
    exit 1
fi

# Determine our CIDR by querying the metadata service
safe_curl -H Metadata:True "http://169.254.169.254/metadata/instance?api-version=2017-12-01&format=json" | jq . > metadata.json
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
	*)
esac

# Format and mount additional SSD, and prefer to use that
for DEV in /dev/sdc /dev/sdd; do
    if test -b ${DEV} && ! test -b "${DEV}1"; then
        mount_device /mnt/ssd  "${DEV}1" SSD2 xfs
        LOCALSTORE=/mnt/ssd
        break
    fi
done

# Node 0 will host NFS shared storage for the cluster
if [ "$MOUNT_TYPE" = nfs ] && [ "$HOSTNAME" = "$NFSHOST" ]; then
    mkdir -p "${LOCALSTORE}/share" "$SHARE"
    clean_fstab "${LOCALSTORE}/share"
    echo "${LOCALSTORE}/share    $SHARE   none   bind   0 0" | tee -a /etc/fstab
    mountpoint -q $SHARE || mount $SHARE
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
    mkdir -p "${SHARE}/xcalar"
    chmod 0777 "${SHARE}/xcalar"
    echo "${SHARE}/xcalar      ${NETWORK}/${MASK}(rw,sync,no_root_squash,no_all_squash)" | tee /etc/exports
    systemctl restart nfs-server
    if firewall-cmd --state; then
        firewall-cmd --permanent --zone=public --add-service=nfs
        firewall-cmd --reload
    fi
fi


### Install Xcalar
if [ -s "installer.sh" ]; then
    # We install our own systemd unit for xcalar in the payload so don't need --startonboot
    if ! bash -x installer.sh --stop --nostart --caddy; then
        echo >&2 "ERROR: Failed to run installer"
        serveError "Failed to run installer" "Please contact Xcalar support at <a href=\"mailto:support@xcalar.com\">support@xcalar.com</a>"
        exit 1
    fi
fi

safe_curl "$CADDY" | gzip -dc > caddy && \
chmod 0755 caddy && \
chown root:root caddy && \
setcap cap_net_bind_service=+ep caddy && \
mv caddy ${XLRDIR}/bin/

# az hangs in telemetry.py occasionally casuing the whole cluster bootup sequence to hang
az_disable_telemetry() {
    local azconfig=$HOME/.azure/config
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
    local exists= created= rc=
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
    MEMBERS+=("${CLUSTER}${ii}")
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
    #aws_route53_record "${CNAME}" "${XCE_DNS}"
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
XCE_XDBSERDESPATH="${INSTANCESTORE}/serdes"
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

mkdir -m 0700 -p $XCE_XDBSERDESPATH && \
chown xcalar:xcalar $XCE_XDBSERDESPATH && \
echo Constants.XdbLocalSerDesPath=$XCE_XDBSERDESPATH
) | tee "$XCE_CONFIG"

if [ -n "$LICENSE" ]; then
    LIC="$(mktemp --tmpdir license.XXXXXX)"
    if echo -n "$LICENSE" | base64 -d | gzip -dc > $LIC; then
        echo >&2 "Decompressed license"
    else
        echo -n "$LICENSE" > $LIC
    fi
    mv $LIC "${XCE_LICENSEDIR}/XcalarLic.key"
    chmod 0644 "${XCE_LICENSEDIR}/XcalarLic.key"
fi

# Make Xcalar config dir writable by xcalar user for config changes via XD
chown -R xcalar:xcalar /etc/xcalar

# Set up the mount for XcalarRoot
mkdir -p "$XCE_HOME"
clean_fstab $XCE_HOME
case "$MOUNT_TYPE" in
    nfs)
        MOUNT_OPTS='noauto,_netdev,x-systemd.automount,nfs,vers=3.0'
        MOUNT_WHAT="${SHARE}"
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
        MOUNT_OPTS="noauto,_netdev,x-systemd.automount,vers=2.1,sec=ntlmssp,credentials=$CREDENTIALS,file_mode=0600,dir_mode=0775,uid=xcalar,gid=xcalar,serverino,mapposix,rsize=1048576,wsize=1048576,echo_interval=60"
        MOUNT_WHAT="//${AZURE_STORAGE_ACCOUNT}.file.core.windows.net/${SHARE}"
        az_storage_share_create "$SHARE"
        ;;
    local)
        chown xcalar:xcalar "$XCE_HOME"
        ;;
esac

if [ "$MOUNT_TYPE" != local ]; then
    cat > /etc/systemd/system/mnt-xcalar.mount <<-EOF
	[Mount]
	What=$MOUNT_WHAT
	Where=$XCE_HOME
	SloppyOptions=on
	DirectoryMode=0777
	Type=$MOUNT_TYPE
	Options=$MOUNT_OPTS
	EOF
    cat > /etc/systemd/system/mnt-xcalar.automount <<-EOF
	[Unit]
	DefaultDependencies=no
	Wants=remote-fs-pre.target
	After=remote-fs-pre.target
	Conflicts=umount.target
	Before=umount.target
	[Automount]
	Where=$XCE_HOME
	TimeoutIdleSec=0
	DirectoryMode=0777
	[Install]
	WantedBy=remote-fs.target
	EOF
    systemctl daemon-reload
    systemctl enable mnt-xcalar.automount
    systemctl start mnt-xcalar.automount
    ls $XCE_HOME  # Force mount of shared dir
    # Wait for share to fully come up. Often times the other nodes get to this point before node0 has
    # even begun
    until mountpoint -q "$XCE_HOME"; do
        echo >&2 "Sleeping ... waiting $XCE_HOME"
        sleep 5
    done
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

# Populate the local host keys with those of the members so we can SSH into them without
# the hostkey check warning
cat ${XCE_HOME}/members/* | tee -a /etc/hosts

while IFS=$'\n' read HOSTENTRY; do
    ssh-keyscan $HOSTENTRY
done < /etc/hosts | tee -a /etc/ssh/ssh_known_hosts


# Add the hosts to ansible
cat ${XCE_HOME}/members/* | awk '{print $(NF)}' | sort -V | tee /etc/ansible/hosts
mv /etc/ansible/ansible.{cfg,bak} || true
cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
inventory    = /etc/ansible/hosts
forks        = 64
roles_path   = ./roles:/etc/ansible/roles
host_key_checking = False
retry_files_enabled = False
[privilege_escalation]
[paramiko_connection]
[ssh_connection]
control_path = %(directory)s/ansible-ssh-%%h-%%p-%%r
[accelerate]
[selinux]
special_context_filesystems=nfs,vboxsf,fuse,ramfs
EOF

# Let's retrieve the xcalar adventure datasets now
if test -n "$XCALAR_ADVENTURE_DATASET"; then
    safe_curl -sSL "$XCALAR_ADVENTURE_DATASET" > xcalarAdventure.tar.gz
    tar -zxvf xcalarAdventure.tar.gz
    mkdir -p /netstore/datasets/adventure
    mv XcalarTraining /netstore/datasets/
    mv dataPrep /netstore/datasets/adventure/
    chmod -R 755 /netstore
fi

systemctl enable xcalar
systemctl start xcalar

# Add in the default admin user into Xcalar
if [ -n "$ADMIN_USERNAME" ]; then
    mkdir -p $XCE_HOME/config
    chown -R xcalar:xcalar $XCE_HOME/config /etc/xcalar
    jsonData="{ \"defaultAdminEnabled\": true, \"username\": \"$ADMIN_USERNAME\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\" }"
    echo "Creating default admin user $ADMIN_USERNAME ($ADMIN_EMAIL)"
    # Don't fail the deploy if this curl doesn't work
    safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "http://127.0.0.1:12124/login/defaultAdmin/setup" || true
    echo
else
    echo "ADMIN_USERNAME is not specified"
fi

if [ -n "$DEPLOYED_URL" ] && [ -n "$WEBHOOK" ]; then
    # Inform license server about URL
    jsonData="{ \"key\": \"$LICENSE\", \"url\": \"$DEPLOYED_URL\", \"marketplaceName\": \"azure\" }"
    safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "$WEBHOOK"
    echo
fi
echo "DONE"
exit
__TARBALL__
