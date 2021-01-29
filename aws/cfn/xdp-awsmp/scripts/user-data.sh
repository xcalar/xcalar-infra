#!/bin/bash
#
# shellcheck disable=SC2086,SC2304,SC2034

set -x
LOGFILE=/var/log/user-data.log
touch $LOGFILE
chmod 0600 $LOGFILE
if [ ! -t 1 ]; then
    exec > >(tee -a $LOGFILE | logger -t user-data -s 2> /dev/console) 2>&1
fi
start=$(date +%s)

log()  {
    local now=$(date +%s)
    local dt=$(( now - start ))
    logger --id -p "local0.info" -t user-data -s dt=\"$dt\" "$@"
}

#Name=tag:aws:autoscaling:groupName,Values=$AWS_AUTOSCALING_GROUPNAME
ec2_find_cluster() {
    aws ec2 describe-instances \
        --filters Name=tag:$1,Values=$2 \
                  Name=instance-state-name,Values=running \
        --query "Reservations[].Instances[].[LaunchTime,AmiLaunchIndex,${3:-PrivateIpAddress}]" \
        --output text | sort -n | awk '{print $(NF)}'
}

asg_healthy_instances() {
    # shellcheck disable=SC2016
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$1" --query 'AutoScalingGroups[].Instances[?HealthStatus==`Healthy`]|[] | length(@)'
}

asg_capacity() {
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$1" --query 'AutoScalingGroups[][MinSize,MaxSize,DesiredCapacity]'  --output text
}

efsip() {
    local EFSIP
    until EFSIP=$(aws efs describe-mount-targets --file-system-id "$1" --query 'MountTargets[?SubnetId==`'$2'`].IpAddress' --output text); do
        log "Waiting for EFS $1 to be up ..."
        sleep 5
    done
    echo "$EFSIP"
}

mbfree() {
    local mb
    if ! mb=$(/bin/df -BM --output=size "$1" | tail -1 | tr -d ' M'); then
        return 1
    fi
    echo "$mb"
}

# $1 = server:/path/to/share
# $2 = /mnt/localpath
mount_xlrroot() {
    local NFSHOST="${1%%:*}"
    local NFSDIR="${1#$NFSHOST}"
    local MOUNT="$2"

    NFSDIR="${NFSDIR#:}"
    NFSDIR="${NFSDIR#/}"

    local existing_mount
    if existing_mount="$(set -o pipefail; findmnt -nT "$2" | awk '{print $2}')"; then
        if [ "$existing_mount" == "$1" ]; then
            log "$1 already mounted to $2"
            return 0
        fi
    fi

    # shellcheck disable=SC2046
    local tmpdir="$(mktemp -d -t nfs.XXXXXX)"
    set +e
    mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=3 $NFSHOST:/$NFSDIR $tmpdir
    local rc=$?
    if [ $rc -eq 32 ]; then
        mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=3 $NFSHOST:/ $tmpdir
        rc=$?
        if [ $rc -eq 0 ]; then
            mkdir -p ${tmpdir}/${NFSDIR}/members
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

ec2_attach_nic() {
    local nic="$1"
    local instance_id="$2"
    if [ -z "$nic" ]; then
        return 1
    fi

    log "Attaching ENI $1 to instance $2"
    local eni_status eni_instance
    while true; do
        eni_status=$(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[].Status' --network-interface-ids ${nic} --output text)
        if [[ "$eni_status" == available ]]; then
            if aws ec2 attach-network-interface --network-interface-id ${nic} --instance-id ${instance_id} --device-index 1; then
                log "ENI $nic attached to $instance_id"
                break
            fi
        fi
        eni_instance=$(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[].Attachment.InstanceId' --network-interface-ids ${nic} --output text)
        if [[ "$eni_instance" == "$instance_id" ]]; then
            log "ENI $nic already attached to $instance_id"
            break
        fi
        log "Waiting for ENI $nic that is $eni_status by $eni_instance .."
        sleep 1
    done
    log "ENI Done"
}

fix_multiline_cert() {
    sed -r 's/(BEGIN|END) PRIVATE KEY/\1PRIVATEKEY/g; s/(BEGIN|END) CERTIFICATE/\1CERTIFICATE/g; s/ /\n/g; s/(BEGIN|END)PRIVATEKEY/\1 PRIVATE KEY/g; s/(BEGIN|END)CERTIFICATE/\1 CERTIFICATE/g'
}

generate_ssl() {
  local name="${1:-some.site.net}"
  local public_ip="${2}"
  local certname=${3:-$name}
  local key="$(pwd)/${certname}.key"
  local crt="$(pwd)/${certname}.crt"

  if test -e "${crt}" && test -e "${key}"; then
      if verify_ssl "$crt" "$key"; then
          echo $crt $key
          return 0
      fi
  fi
  cat <<EOF | openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout ${key} -out ${crt} -extensions san -subj "/C=US/ST=CA/L=San Jose/O=XcalarInc/OU=Self signed Root CA/CN=${name%%.*}" -config /dev/stdin
[req]
distinguished_name=req
[san]
subjectAltName=DNS.1:${name},DNS.2:localhost,IP.1:$(hostname -i),IP.2:127.0.0.1${public_ip:+,IP.3:$public_ip}
EOF
    chmod 0640 $key
    echo $crt $key
}

verify_ssl() {
    local crt="$1"
    local key="$2"

    local keyfpmd5=$(openssl rsa -modulus -noout -in $key | openssl md5 | cut -d' ' -f2)
    local crtfpmd5=$(openssl x509 -modulus -noout -in $crt | openssl md5 | cut -d' ' -f2)

    if [ "$keyfpmd5" != "$crtfpmd5" ]; then
        echo >&2 "WARN: Mismatch fingerprints for $crt and $key"
        return 1
    fi
    if [ $(openssl x509 -noout -text -in $crt | grep -c Subject) -eq 0 ]; then
        echo >&2 "WARN: No subjects in $crt and $key"
        return 1
    fi
    return 0
}

generate_caddy() {
    local caddyfile="$1"
    local crt="$2"
    local key="$3"

    eval $(grep -E '(XCE_LOGIN_PAGE|XCE_ACCESS_URL)' /etc/default/xcalar | sed 's/^#//')
    echo "https://0.0.0.0:443, http://0.0.0.0:80 {"
    # shellcheck disable=SC2016
    tail -n+2 $caddyfile \
        | sed '/redir 301/,+4d' \
        | sed 's@tls self_signed.*$@tls '$crt' '$key'@' \
        | sed 's@{\$XCE_LOGIN_PAGE}@'$XCE_LOGIN_PAGE'@' \
        | sed 's@{\$XCE_ACCESS_URL}@'$XCE_ACCESS_URL'@' \

}


main() {
    eval $(ec2-tags -s -i)
    mkdir -p /var/tmp/xcalar-root
    chown xcalar:xcalar /var/tmp/xcalar-root

    if ((SYSTEMD)); then
        systemctl stop xcalar-services.target || true
    else
        /etc/init.d/xcalar stop-supervisor || true
    fi

    # shellcheck disable=SC2046
    ENV_FILE=/var/lib/cloud/instance/ec2.env

    if [ -e "$ENV_FILE" ]; then
        . $ENV_FILE
    fi

    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            --nic)
                NIC="$1"
                shift
                ;;
            --subnet)
                SUBNET="$1"
                shift
                ;;
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
            --bucket)
                BUCKET="$1"
                shift
                ;;
            --prefix)
                PREFIX="$1"
                shift
                ;;
            --cluster-size)
                CLUSTER_SIZE="$1"
                shift
                ;;
            --ssl-cert)
                SSLCRT="$1"
                echo "$1" > /etc/xcalar/host.crt
                chown root:xcalar /etc/xcalar/host.crt
                chmod 0644 /etc/xcalar/host.crt
                shift
                ;;
            --ssl-key)
                SSLKEY="$1"
                echo "$1" > /etc/xcalar/host.key
                chown root:xcalar /etc/xcalar/host.key
                chmod 0640 /etc/xcalar/host.key
                shift
                ;;
            --node-id)
                NODE_ID="$1"
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
            --cluster-name)
                CLUSTER_NAME="$1"
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
                log "WARNING: Unknown command $cmd"
                ;;
        esac
    done

    CLUSTER_SIZE=${CLUSTER_SIZE:-1}
    XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
    XCE_TEMPLATE=${XCE_TEMPLATE:-/etc/xcalar/template.cfg}
    EPHEMERAL=/ephemeral/data

    RELEASE_NAME=$(rpm -qf /etc/system-release --qf '%{NAME}')
    RELEASE_VERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
    case "$RELEASE_VERSION" in
        6 | 6*) OSID=el6; INIT=sysvinit; SYSTEMD=0;;
        7 | 7*) OSID=el7; INIT=systemd; SYSTEMD=1;;
        201*) OSID=amzn1; INIT=sysvinit; SYSTEMD=0;;
        2) OSID=amzn2; INIT=systemd; SYSTEMD=1;;
        *)
            log "ERROR: Unknown OS version $RELEASE_VERSION"
            exit 1
            ;;
    esac
    if ((SYSTEMD)); then
        if test -e /lib/systemd/system/xcalar-services.target; then
            SYSTEMD_UNIT=xcalar-services.target
        else
            SYSTEMD_UNIT=xcalar.service
        fi
    fi

    INSTANCE_ID=$(curl -sSf http://169.254.169.254/latest/meta-data/instance-id)
    AVZONE=$(curl -sSf http://169.254.169.254/latest/meta-data/placement/availability-zone)
    INSTANCE_TYPE=$(curl -sSf http://169.254.169.254/latest/meta-data/instance-type)
    LOCAL_IPV4=$(curl -sSf http://169.254.169.254/latest/meta-data/local-ipv4)
    LOCAL_HOSTNAME=$(curl -sSf http://169.254.169.254/latest/meta-data/local-hostname)
    sed -i "/^${LOCAL_IPV4}/d; /${LOCAL_HOSTNAME}/d;" /etc/hosts
    echo "$LOCAL_IPV4	$LOCAL_HOSTNAME     $(hostname -s)" | tee -a /etc/hosts

    export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"

    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin:/opt/mssql-tools/bin:/opt/xcalar/bin
    echo "export PATH=$PATH" > /etc/profile.d/path.sh

    NFSHOST="${NFSMOUNT%%:*}"
    NFSDIR="${NFSMOUNT#$NFSHOST}"
    NFSDIR="${NFSDIR#:}"
    NFSDIR="${NFSDIR#/}"

    if [ -z "$NFS_TYPE" ]; then
        if [[ $NFSHOST =~ ^fs-[0-9a-f]{8}$ ]]; then
            if [ -n "$SUBNET" ]; then
                if EFSIP="$(efsip $NFSHOST $SUBNET)"; then
                    NFSHOST=$EFSIP
                    NFS_TYPE=nfs
                    NFS_OPTS="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
                fi
            else
                NFS_TYPE=efs
                NFS_OPTS="_netdev"
            fi
        else
            NFS_TYPE=nfs
            NFS_OPTS="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
        fi
    fi

    XCE_LICENSE=/etc/xcalar/XcalarLic.key
    if [ ! -s $XCE_LICENSE ] && [ -n "$LICENSE" ]; then
        if [[ $LICENSE =~ ^s3:// ]]; then
            aws s3 cp $LICENSE - | base64 -d | gzip -dc > $XCE_LICENSE
        elif [[ $LICENSE =~ ^https:// ]]; then
            curl -fsSL "$LICENSE" | base64 -d | gzip -dc > $XCE_LICENSE
        else
            echo "$LICENSE" | base64 -d | gzip -dc > $XCE_LICENSE
        fi
        if [ ${PIPESTATUS[2]} -ne 0 ]; then
            echo "ERROR: Failed to decode license"
            truncate -s 0 $XCE_LICENSE
        fi
        touch $XCE_LICENSE
        chown xcalar:xcalar $XCE_LICENSE
        chmod 0600 $XCE_LICENSE
    fi

    if [ -n "$TAG_KEY" ] && [ -z "$TAG_VALUE" ]; then
        # shellcheck disable=SC2153
        case "$TAG_KEY" in
            aws:autoscaling:groupName)
                TAG_VALUE="$AWS_AUTOSCALING_GROUPNAME"
                ;;
            aws:cloudformation:stack-name)
                TAG_VALUE="$AWS_CLOUDFORMATION_STACK_NAME"
                ;;
            ClusterName)
                TAG_VALUE="$CLUSTERNAME"
                ;;
            Name)
                TAG_VALUE="$NAME"
                ;;
            *)
                log "WARNING: Unrecognized clustering tag: TAG_KEY=$TAG_KEY"
                ;;
        esac
    fi

    if [ -z "$TAG_KEY" ]; then
        if [ -n "$AWS_AUTOSCALING_GROUPNAME" ]; then
            TAG_KEY=aws:autoscaling:groupName
            TAG_VALUE=$AWS_AUTOSCALING_GROUPNAME
        elif [ -n "$AWS_CLOUDFORMATION_STACK_NAME" ]; then
            TAG_KEY=aws:cloudformation:stack-name
            TAG_VALUE=$AWS_CLOUDFORMATION_STACK_NAME
        elif [ -n "$CLUSTERNAME" ]; then
            TAG_KEY=ClusterName
            TAG_VALUE="$CLUSTERNAME"
        elif [ -n "$NAME" ]; then
            TAG_KEY=Name
            TAG_VALUE=$NAME
        else
            log "No valid tags found"
        fi
    fi

    if [ -n "$TAG_KEY" ] && [ -n "$TAG_VALUE" ]; then
        IPS=()
        while true; do
            if IPS=($(ec2_find_cluster "$TAG_KEY" "$TAG_VALUE")); then
                NUM_INSTANCES="${#IPS[@]}"
                if [ $NUM_INSTANCES -gt 0 ]; then
                    log "Found $NUM_INSTANCES cluster members!"
                    if [ -z "$CLUSTER_SIZE" ]; then
                        break
                    fi
                    if [ $NUM_INSTANCES -eq $CLUSTER_SIZE ]; then
                        break
                    fi
                fi
            fi
            sleep 2
        done
        for NODE_ID in $(seq 0 $((NUM_INSTANCES-1))); do
            if [ "$LOCAL_IPV4" == "${IPS[$NODE_ID]}" ]; then
                break
            fi
        done
        if [ "$LOCAL_IPV4" != "${IPS[$NODE_ID]}" ]; then
            log "WARNING: Unable to find $LOCAL_IPV4 in the list of IPS: ${IPS[*]}"
        fi
    else
        IPS=( "$LOCAL_IPV4" )
        NODE_ID=0
    fi

    aws ec2 create-tags --resources $INSTANCE_ID \
            --tags Key=Name,Value="${AWS_CLOUDFORMATION_STACK_NAME}-${NODE_ID}" \
                Key=Node_ID,Value="${NODE_ID}"

    MOUNT_OK=false
    XLRROOT=/var/opt/xcalar
    if [ -n "$NFSMOUNT" ]; then
        mkdir -p /mnt/xcalar
        if mount_xlrroot $NFSHOST:/${NFSDIR:-cluster/$CLUSTER_NAME} /mnt/xcalar; then
            MOUNT_OK=true
            XLRROOT=/mnt/xcalar
        else
            rmdir /mnt/xcalar
        fi
    fi
    if [ "$MOUNT_OK" = true ]; then
        if ! test -d ${XLRROOT}/jupyterNotebooks; then
            rsync -avzr /var/opt/xcalar/ ${XLRROOT}/
        fi
    else
        XLRROOT=/var/opt/xcalar
        mkdir -p $XLRROOT
        IPS=($(hostname -i))
        NUM_INSTANCES=1
    fi
    chown xcalar:xcalar $XLRROOT

    # Customize the template
    cp -n "$XCE_TEMPLATE" "${XCE_TEMPLATE%.*}.bak"
    sed -i '/^Constants.XcalarRootCompletePath/d' $XCE_TEMPLATE
    sed -i "4i Constants.XcalarRootCompletePath=$XLRROOT" $XCE_TEMPLATE
    sed -i '/Constants.Cgroups/d' ${XCE_TEMPLATE}
    if [ -n "${CGROUPS_ENABLED:-}" ]; then
        if [ "$CGROUPS_ENABLED" != true ]; then
            sed -i '4i Constants.Cgroups=false' $XCE_TEMPLATE
        fi
    fi

    sed -i '/^Constants.XdbSerDesMode/d; /^Constants.XdbLocalSerDesPath/d; /^Constants.XdbSerDesMaxDiskMB/d' $XCE_TEMPLATE

    if test -e /etc/xcalar/Caddyfile; then
        if ! test -L /etc/xcalar/Caddyfile; then
            cp -n /etc/xcalar/Caddyfile /etc/xcalar/Caddyfile.orig
        fi
    fi
    if [ $NODE_ID -eq 0 ]; then
        ec2_attach_nic "$NIC" "$INSTANCE_ID"
        test -d $XLRROOT/config || mkdir -p $XLRROOT/config
        PUBLIC_DNS_AND_IP="$(aws ec2 describe-network-interfaces --network-interface-ids $NIC --query 'NetworkInterfaces[].Association.[PublicDnsName,PublicIp]' --output text)"
        if test -s /etc/xcalar/host.crt && test -s /etc/xcalar/host.key; then
            CRT_KEY=($XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.crt $XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.key)
            fix_multiline_cert < /etc/xcalar/host.crt > "${CRT_KEY[0]}"
            fix_multiline_cert < /etc/xcalar/host.key > "${CRT_KEY[1]}"
            if ! verify_ssl "${CRT_KEY[@]}"; then
                rm -f "${CRT_KEY[@]}"
                CRT_KEY=($(cd $XLRROOT/config && generate_ssl $PUBLIC_DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
            fi
        else
            CRT_KEY=($(cd $XLRROOT/config && generate_ssl $PUBLIC_DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
        fi
        chown root:xcalar "${CRT_KEY[@]}"
        chmod 0644 "${CRT_KEY[0]}"
        chmod 0640 "${CRT_KEY[1]}"

        generate_caddy /etc/xcalar/Caddyfile.orig "${CRT_KEY[@]}" > $XLRROOT/config/Caddyfile.$$ \
        && mv $XLRROOT/config/Caddyfile.$$ $XLRROOT/config/Caddyfile
        /opt/xcalar/scripts/genDefaultAdmin.sh \
            --username "${ADMIN_USERNAME}" \
            --email "${ADMIN_EMAIL:-info@xcalar.com}" \
            --password "${ADMIN_PASSWORD}" > /tmp/defaultAdmin.json \
            && mv /tmp/defaultAdmin.json $XLRROOT/config/defaultAdmin.json
        chmod 0700 $XLRROOT/config
        chmod 0600 $XLRROOT/config/defaultAdmin.json $XLRROOT/config/*.key
        chown xcalar:xcalar $XLRROOT/config $XLRROOT/config/*
    fi

    ln -sfn $XLRROOT/config/Caddyfile /etc/xcalar/Caddyfile

    if rpm -q ephemeral-disk; then
        local dt=0
        until mountpoint -q $EPHEMERAL; do
            sleep 1
            dt=$((dt+1))
            log "Waiting for $EPHEMERAL ..."
            if [ $dt -gt 120 ]; then
                break
            fi
        done
    fi

    if mountpoint -q "$EPHEMERAL"; then
        XCE_XDBSERDESPATH=${XCE_XDBSERDESPATH:-${EPHEMERAL}/serdes}
    fi
    if [ ! -d "$XCE_XDBSERDESPATH" ]; then
        if ! mkdir -m 0700 "$XCE_XDBSERDESPATH"; then
            XCE_XDBSERDESPATH=''
        fi
    fi

    if [ -d "$XCE_XDBSERDESPATH" ]; then
        chown xcalar:xcalar "$XCE_XDBSERDESPATH"
        XCE_XDBSERDESMB=$(( $(mbfree $XCE_XDBSERDESPATH) - 1000 ))
        if [[ $XCE_XDBSERDESMB -gt 0 ]]; then
            sed -i "4i Constants.XdbSerDesMode=2" $XCE_TEMPLATE
            sed -i "4i Constants.XdbLocalSerDesPath=$XCE_XDBSERDESPATH" $XCE_TEMPLATE
            sed -i "4i Constants.XdbSerDesMaxDiskMB=$XCE_XDBSERDESMB" $XCE_TEMPLATE
        fi
    fi

    /opt/xcalar/scripts/genConfig.sh ${XCE_TEMPLATE} - "${IPS[@]}" > $XCE_CONFIG
    log "Starting Xcalar"

    if ((SYSTEMD)); then
        systemctl start $SYSTEMD_UNIT
    else
        /etc/init.d/xcalar start
    fi
    rc=$?

    if ((SYSTEMD)); then
        systemctl enable $SYSTEMD_UNIT
    else
        chkconfig xcalar on
    fi


    log "All done with user-data.sh (rc=$rc)"
    exit $rc
}

main "$@"
