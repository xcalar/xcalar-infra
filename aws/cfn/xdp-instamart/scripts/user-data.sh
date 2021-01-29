#!/bin/bash
#
# shellcheck disable=SC2086,SC2304,SC2034,SC2206,SC2207,SC2046

bootstrap_init() {
    set -x
    set +e
    start=$(date +%s)
    export IMDSV2='latest'
    export IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/${IMDSV2}/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    export PS4='-> $(date +%F\ %T.%N%z) $(basename ${BASH_SOURCE[0]:-noscript}):${LINENO:-0}: ${FUNCNAME[0]:-nofunc} $? : '
    LOGFILE=/var/log/user-data.log
    touch $LOGFILE
    chmod 0600 $LOGFILE
    if [ ! -t 1 ]; then
        exec > >(tee -a $LOGFILE | logger -t user-data -s 2> /dev/console) 2>&1
    fi
}

log() {
    local now=$(date +%s)
    local dt=$((now - start))
    logger --id -p "local0.info" -t user-data -s dt=\"$dt\" "$@"
}

# Instance meta-data service v2
imds() {
    curl -f -s -L -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/$IMDSV2/${1#/}"
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
    local prop="${2:-DesiredCapacity}"
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$1" --query 'AutoScalingGroups[].['$prop']' --output text
}

efsip() {
    local efsip_
    until efsip_=$(aws efs describe-mount-targets --file-system-id "$1" --query 'MountTargets[?SubnetId==`'$2'`].IpAddress' --output text); do
        log "Waiting for EFS $1 to be up ..."
        sleep 2
    done
    echo "${efsip_}"
}

asg_get_instance_protection() {
    local protected
    [ $# -gt 0 ] || set -- $INSTANCE_ID
    if protected=$(aws autoscaling describe-auto-scaling-instances --instance-ids $1 --query 'AutoScalingInstances[].ProtectedFromScaleIn' --output text); then
        if [ "$protected" = True ] || [ "$protected" = true ]; then
            return 0
        fi
    fi
    return 1
}

asg_set_instance_protection() {
    [ $# -gt 0 ] || set -- "$INSTANCE_ID" true "$AWS_AUTOSCALING_GROUPNAME"
    local instance_id="$1" protected="${2:-true}" asg="${3:-$AWS_AUTOSCALING_GROUPNAME}"
    case "$protected" in
        [Ff]alse) aws autoscaling set-instance-protection  --instance-ids "$instance_id" --auto-scaling-group-name "$asg" --no-protected-from-scale-in;;
        *) aws autoscaling set-instance-protection  --instance-ids "$instance_id" --auto-scaling-group-name "$asg" --protected-from-scale-in;;
    esac
}

mbfree() {
    local mb
    if ! mb=$(/bin/df -BM --output=size "$1" | tail -1 | tr -d ' M'); then
        echo "0"
        return 1
    fi
    echo "$mb"
}

# $1 = server:/path/to/share
# $2 = /mnt/localpath
mount_xlrroot() {
    local nfshost="${1%%:*}"
    local nfsdir="${1#$nfshost}"
    local mount="$2"

    nfsdir="${nfsdir#:}"
    nfsdir="${nfsdir#/}"

    local existing_mount
    if existing_mount="$(
        set -o pipefail
        findmnt -nT "$2" | awk '{print $2}'
    )"; then
        if [ "$existing_mount" = "$1" ]; then
            log "$1 already mounted to $2"
            return 0
        fi
    fi

    # shellcheck disable=SC2046
    local rc tmpdir
    tmpdir=/efs
    mkdir -p $tmpdir $mount
    until mountpoint -q $mount; do
        if mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=60 $nfshost:/$nfsdir $mount; then
            continue
        fi
        if mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=60 $nfshost:/ $tmpdir; then
            mkdir -p ${tmpdir}/${nfsdir}
            chmod 0700 ${tmpdir}/${nfsdir}
            chown xcalar:xcalar ${tmpdir}/${nfsdir}
            umount $tmpdir
            continue
        fi
    done
    if mountpoint -q "$mount"; then
        sed -i '\@'$mount'@d' /etc/fstab
        echo "${nfshost}:/${nfsdir} $mount $NFS_TYPE  $NFS_OPTS 0 0" >> /etc/fstab
        test -d $mount || mkdir -p $mount
        mountpoint -q $mount || mount $mount
    else
        mount $mount
    fi
    rc=$?
    return $rc
}

shutdown_node() {
    echo >&2 "Shutting down node $NODE_ID: $INSTANCE_ID"
    for ii in $(seq 0 10); do
        ec2_detach_nic && break
        sleep 2
    done
    systemctl stop xcalar.service
    shutdown -h now
}

ec2_detach_nic() {
    ENI_ATTACHMENT=${ENI_ATTACHMENT:-/run/eni-attachment.txt}
    local attachment
    if attachment=$(cat $ENI_ATTACHMENT 2>/dev/null); then
        if aws ec2 detach-network-interface --attachment-id "$attachment"; then
            echo >&2 "Detatched ENI: $attachment"
            rm -f $ENI_ATTACHMENT
        else
            echo >&2 "Failed to detatch ENI: $attachment"
            return 1
        fi
    fi
    return 0
}

ec2_attach_nic() {
    local nic="$1"
    local instance_id="$2"
    if [ -z "$nic" ]; then
        return 1
    fi

    log "Attaching ENI $1 to instance $2"
    local eni_attr eni_status eni_instance
    ENI_ATTACHMENT=${ENI_ATTACHMENT:-/run/eni-attachment.txt}
    while true; do
        eni_attr=($(aws ec2 describe-network-interface-attribute --network-interface-id ${nic} --attribute attachment --query 'Attachment.[Status,InstanceId,AttachmentId]' --output text))
        eni_status="${eni_attr[0]}"
        eni_instance="${eni_attr[1]}"
        if [ "$eni_instance" = "$instance_id" ]; then
            log "ENI $nic already attached to $instance_id"
            break
        fi
        if [ -z "$eni_instance" ] || [ -z "$eni_status" ] || [ "$eni_status" = None ] || [ "$eni_status" = available ]; then
            if aws ec2 attach-network-interface --network-interface-id ${nic} --instance-id ${instance_id} --device-index 1 --query 'AttachmentId' --output text > "$ENI_ATTACHMENT".$$; then
                log "ENI $nic attached to $instance_id, was $eni_status"
                mv "$ENI_ATTACHMENT".$$ "$ENI_ATTACHMENT"
                break
            fi
            if aws ec2 detach-network-interface --attachment-id "${eni_attr[2]}"; then
                log "ENI $nic detached from ${eni_attr[2]}"
            fi
        fi
        log "Waiting for ENI $nic that is $eni_status by $eni_instance .."
        sleep 2
    done
    log "ENI Done"
}

fix_multiline_cert() {
    sed -r 's/(BEGIN|END) PRIVATE KEY/\1PRIVATEKEY/g; s/(BEGIN|END) CERTIFICATE/\1CERTIFICATE/g; s/ /\n/g; s/(BEGIN|END)PRIVATEKEY/\1 PRIVATE KEY/g; s/(BEGIN|END)CERTIFICATE/\1 CERTIFICATE/g'
}

selfsigned_cert() {
    local name="${1:-some.site.net}"
    local public_ip="${2}" tmp=
    local certname=${3:-$name}
    local key="${certname}.key"
    local crt="${certname}.crt"

    if [ "${name%%.*}" != "${name}" ]; then
        local domain="${name#*.}"
    fi

    if ! openssl req -x509 -newkey rsa:4096 -sha256 -utf8 -days 365 -nodes -keyout $key -out $crt -config <(
        cat << EOF
[CA_default]
copy_extensions = copy

[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[req_distinguished_name]
C = US
ST = CA
L = San Jose
CN = ${name}

[v3_ca]
basicConstraints = critical, CA:FALSE
subjectAltName = @alternate_names

keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alternate_names

[alternate_names]
DNS.1 = $name
DNS.2 = localhost
DNS.3 = *.localhost
${domain:+DNS.4 = *.${domain}}
IP.4 = ${public_ip}
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
    ); then
        echo >&3 "Failed to generate OpenSSL cert. See $tmp"
        return 1
    fi
    return 0
}

generate_ssl() {
    local name="${1:-some.site.net}"
    local public_ip="${2}" tmp=
    local certname=${3:-$name}
    local key="$(pwd)/${certname}.key"
    local crt="$(pwd)/${certname}.crt"

    if test -e "${crt}" && test -e "${key}"; then
        if verify_ssl "$crt" "$key"; then
            echo $crt $key
            return 0
        fi
        rm -f $crt $key
    fi
    if ! selfsigned_cert "$@"; then
        if /etc/ssl/certs/make-dummy-cert $certname > /dev/null; then
            sed -n '/---BEGIN CERT/,/---END CERT/p' $certname > $crt
            sed -n '/---BEGIN PRIVATE/,/---END PRIVATE/p' $certname > $key
            rm -f $certname
        else
            return 1
        fi
    fi
    chmod 0600 $key
    echo $crt $key
}

verify_ssl() {
    local crt="$1"
    local key="$2"
    local keyfpmd5 crtfpmd5

    if ! keyfpmd5=$(openssl rsa -modulus -noout -in $key | openssl md5 | cut -d' ' -f2); then
        return 1
    fi
    if ! crtfpmd5=$(openssl x509 -modulus -noout -in $crt | openssl md5 | cut -d' ' -f2); then
        return 1
    fi

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

xmkdir() {
    local mode='0755' u='xcalar' g='' parents='' dir ug
    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            -m) mode="$1"; shift;;
            -u) u="$1"; shift;;
            -g) g="$1"; shift;;
            -p) parents="-p";;
            *)
                dir="$cmd"
                ug="${u}:${g:-$u}"
                if ! test -e "$dir"; then
                    if ! mkdir -m "1777" $parents "$dir"; then
                        echo >&2 "Couldn't create $dir (mode: $mode, ug: $ug)"
                        return 1
                    fi
                    chown "$ug" "$dir"
                    chmod "$mode" "$dir"
                    continue
                fi
                if [ "$(stat -c '%U:%G' "$dir")" != "$ug" ]; then
                    chown "$ug" "$dir"
                fi
                if [ "$(stat -c '%a' "$dir")" != "${mode#0}" ]; then
                    chmod "$mode" "$dir"
                fi
                ;;
        esac
    done
    return 0
}

get_default() {
    awk -F'=' '$1 == "'$1'" {print $2}' $PREFIX/etc/default/xcalar /etc/default/xcalar | tail -1
}

generate_caddy() {
    local caddyfile="$1"
    local crt="$2"
    local key="$3"

    XCE_LOGIN_PAGE=$(get_default XCE_LOGIN_PAGE)
    XCE_ACCESS_URL=$(get_default XCE_ACCESS_URL)

    echo "https://0.0.0.0:443, http://0.0.0.0:80 {"
    # shellcheck disable=SC2016,SC2015
    tail -n+2 $caddyfile \
        | sed '/redir 301/,+4d' \
        | sed '/Strict-Transport-Security/d' \
        | (test -e "$crt" && sed 's@tls self_signed.*$@tls '$crt' '$key'@' || cat -) \
        | sed 's@{\$XCE_LOGIN_PAGE}@'$XCE_LOGIN_PAGE'@' \
        | sed 's@{\$XCE_ACCESS_URL}@'$XCE_ACCESS_URL'@'
}

systemd_haveunit() {
    test -e /lib/systemd/system/$1 || test -e /etc/systemd/system/$1
}

systemd_wait_xcalar() {
    local cnt=0 timeout=${1:-60} start
    echo >&2 "Waiting for xcalar to stop ..."
    start=$(date +%s)
    for((cnt=0; cnt < timeout; cnt++)); do
        if ! pidof usrnode childnode xcmonitor xcmgmtd  >/dev/null; then
            if ! pgrep -af sqldf >/dev/null; then
                echo >&2 "Xcalar stopped after $(($(date +%s) - start)) seconds"
                return 0
            fi
        fi
        sleep 1
    done
    echo >&2 "Failed to wait for stop after $timeout seconds"
    return 1
}

pyver() {
    $1 -c "from __future__ import print_function; import sys; vi=sys.version_info; print(\"{}.{}\".format(vi.major,vi.minor)"
}

pyvenv() {
    local venv="$1" python="${2:-$PREFIX/bin/python3}"

    ver=$(pyver $python)
    export PIP_FIND_LINKS=/var/lib/wheels-${ver}

    $python -m venv $venv \
    && $venv/bin/python -m pip install -U pip \
    && $venv/bin/python -m pip install -U setuptools wheel pip-tools
}

file_size() {
    # $1 = file
    # $2 = minimum file size
    local sz
    if ! sz=$(stat -c %s "$1"); then
        return 1
    fi
    echo "$sz"
    if [ -z "$2" ]; then
        return 0
    fi
    if [ $sz -ge $2 ]; then
        return 0
    fi
    return 1
}

copysshkeys() {
    XCE_USER_HOME=${XCE_USER_HOME:-/home/xcalar}
    SSHDIR=$XCE_USER_HOME/.ssh
    mkdir -p $SSHDIR
    chmod 0700 $SSHDIR
    touch $SSHDIR/config $SSHDIR/authorized_keys
    touch ${XCE_USER_HOME}/.hushlogin
    chmod 0600 ${SSHDIR}/authorized_keys ${SSHDIR}/config
    chown xcalar:xcalar $XCE_USER_HOME $SSHDIR ${SSHDIR}/* ${XCE_USER_HOME}/.hushlogin
    if mountpoint -q "$XLRROOT"; then
        until test -e "$XLRROOT"/config/id_rsa.pub; do
            sleep 1
        done
        cat ${XLRROOT}/config/id_rsa.pub >> ${SSHDIR}/authorized_keys
    fi
}

# shellcheck disable=SC2181,SC2174
main() {
    bootstrap_init

    local ii rc

    eval $(ec2-tags -s)
    if [ -n "$CLUSTERNAME" ]; then
        ClusterName="$CLUSTERNAME"
        unset CLUSTERNAME
    fi


    RELEASE_NAME=$(rpm -qf /etc/system-release --qf '%{NAME}')
    RELEASE_VERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
    SYSTEMD=1
    case "$RELEASE_VERSION" in
        6 | 6*)
            OSID=el6
            SYSTEMD=0
            ;;
        7 | 7*)
            OSID=el7
            ;;
        8 | 8*)
            OSID=el8
            ;;
        201*)
            OSID=amzn1
            SYSTEMD=0
            ;;
        2)
            OSID=amzn2
            ;;
        *)
            log "ERROR: Unknown OS version $RELEASE_VERSION"
            exit 1
            ;;
    esac

    # shellcheck disable=SC2046
    DEFAULTS=/opt/xcalar/etc/default/xcalar
    ENV_FILE=/var/lib/cloud/instance/ec2.env
    CLOUD_ENV_FILE=/var/lib/cloud/instance/cloud.env

    if [ -e "$ENV_FILE" ]; then
        . $ENV_FILE
    fi

    if [ -e "$CLOUD_ENV_FILE" ]; then
        . $CLOUD_ENV_FILE
    fi

    PREFIX=${PREFIX:-/opt/xcalar}
    SSLKEYFILE=${SSLKEYFILE:-/etc/xcalar/host.key}
    SSLCRTFILE=${SSLCRTFILE:-/etc/xcalar/host.crt}
    SITE_DIR=$($PREFIX/bin/python3 -c 'import site; print(site.getsitepackages()[-1])')
    PTHFILE=${SITE_DIR}/mnt-xcalar-pysite.pth
    SENDSUPPORT=${SENDSUPPORT:-true}
    SHAREDIR=${SHAREDIR:-/mnt/xcalar}
    BOOTCMD=""
    PUBLICIP=0
    ENI_ATTACHMENT="${ENI_ATTACHMENT:-/run/eni-attachment.txt}"

    while [ $# -gt 0 ]; do
        local cmd="$1"
        shift
        case "$cmd" in
            --boot-cmd)
                BOOTCMD="$1"
                shift
                ;;
            --no-sendsupport)
                SENDSUPPORT=false
                ;;
            --nic)
                NIC="$1"
                shift
                ;;
            --asg-name)
                ASG_NAME="$1"
                shift
                ;;
            --stack-name)
                STACK_NAME="$1"
                shift
                ;;
            --subnet)
                SUBNET="$1"
                shift
                ;;
            --efs-target)
                EFSTARGET="$1"
                shift
                ;;
            --efs-target-ip)
                EFSTARGETIP="$1"
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
            --efs-id)
                EFSID="$1"
                shift
                ;;
            --efs-ip)
                EFSIP="$1"
                shift
                ;;
            --efs-ap)
                EFSAP="$1"
                shift
                ;;
            --nfs-opts)
                NFS_OPTS="$1"
                shift
                ;;
            --mount-dir)
                MOUNT_DIR="$1"
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
            --eni-attachment)
                ENI_ATTACHMENT="$1"
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
            --secret-id)
                SECRETID="$1"
                shift
                ;;
            --ssl-cert)
                SSLCRT="$1"
                echo "$1" > $SSLCRTFILE
                chown root:xcalar $SSLCRTFILE
                chmod 0644 $SSLCRTFILE
                shift
                ;;
            --ssl-key)
                SSLKEY="$1"
                echo "$1" > $SSLKEYFILE
                chown xcalar:xcalar $SSLKEYFILE
                chmod 0600 $SSLKEYFILE
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
            --public-ip)
                if [ "${1,}" = true ]; then
                    PUBLICIP=1
                else
                    PUBLICIP=0
                fi
                shift
                ;;
            --admin-username)
                ADMIN_USERNAME="$1"
                shift
                ;;
            --admin-password-file)
                ADMIN_PASSWORD_FILE="$1"
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
            --sharedir)
                SHAREDIR="$1"
                shift
                ;;
            *)
                log "WARNING: Unknown command $cmd"
                ;;
        esac
    done

    if [ -z "$ASG_NAME" ]; then
        ASG_NAME="$AWS_AUTOSCALING_GROUPNAME"
    fi

    declare -g DESIRED=$(asg_capacity "$AWS_AUTOSCALING_GROUPNAME")
    if [ -z "$CLUSTER_SIZE" ]; then
        CLUSTER_SIZE=$DESIRED
    fi
    if [ "$BOOTCMD" = restart ]; then
        systemctl stop xcalar.service || true
        CONFIG_ONLY=1
    else
        CONFIG_ONLY=0
    fi

    XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
    XCE_TEMPLATE=${XCE_TEMPLATE:-/etc/xcalar/template.cfg}
    EPHEMERAL=${EPHEMERAL:-/ephemeral/data}

    if ((SYSTEMD)); then
        if test -e /lib/systemd/system/xcalar-services.target; then
            SYSTEMD_UNIT=xcalar-services.target
        else
            SYSTEMD_UNIT=xcalar.service
        fi
    fi

    INSTANCE_ID=$(imds /meta-data/instance-id)
    AVZONE=$(imds /meta-data/placement/availability-zone)
    INSTANCE_TYPE=$(imds /meta-data/instance-type)
    LOCAL_IPV4=$(imds /meta-data/local-ipv4)
    LOCAL_HOSTNAME=$(imds /meta-data/local-hostname)
    PUBLIC_IPV4=$(imds /meta-data/public-ipv4)
    export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"
    export AWS_REGION="$AWS_DEFAULT_REGION"
    if ((CONFIG_ONLY)); then
        :
    else
        sed -i "/^${LOCAL_IPV4}/d; /${LOCAL_HOSTNAME}/d;" /etc/hosts
        echo "$LOCAL_IPV4	$LOCAL_HOSTNAME     $(hostname -s)" | tee -a /etc/hosts


        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin:/opt/mssql-tools/bin:$PREFIX/bin
        echo "export PATH=$PATH" > /etc/profile.d/path.sh


        sed -i -r 's/stunnel_check_cert_hostname.*/stunnel_check_cert_hostname = false/' /etc/amazon/efs/efs-utils.conf
        mkdir -p /mnt/efs
        EFSFQDN="${EFSID}.efs.${AWS_DEFAULT_REGION}.amazonaws.com"
        EFSDNSIP=$(set -o pipefail; host ${EFSFQDN} | awk '{print $NF}')
        if [ $? -eq 0 ] && [[ $EFSDNSIP =~ ^([0-9\.]+) ]]; then
            MYNFSIP="$EFSDNSIP"
        elif [ -n "$EFSIP" ]; then
            MYNFSIP="$EFSIP"
        elif [ -n "$EFSTARGETIP" ]; then
            MYNFSIP="$EFSTARGETIP"
        fi
        if [ -n "$MYNFSIP" ]; then
            sed -i '/mynfs/d' /etc/hosts
            echo "$MYNFSIP     $EFSFQDN   $EFSID   mynfs" >> /etc/hosts
        fi

        TYPES=(efs efs efs nfs4 nfs4 nfs4)
        OPTS=(
            "tls,${EFSAP:+accesspoint=$EFSAP,}iam"
            "tls"
            "tls"
            "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,retrans=2,noresvport"
            "nfsvers=4.1,rsize=1048576,wsize=1048576,hard,retrans=2,noresvport"
            "rsize=1048576,wsize=1048576,hard,retrans=2,noresvport,defaults"
        )
        HOSTS=("$EFSID" "$EFSID" "$EFSID" ${MYNFSIP})

        if [ -n "$EFSIP" ] && [ "$MYNFSIP" != "$EFSIP" ]; then
            HOSTS+=("${EFSIP}")
        fi
        if [ -n "$EFSTARGETIP" ] && [ "$EFSTARGETIP" != "$EFSIP" ]; then
            HOSTS+=("${EFSTARGETIP}")
        fi

        EFSMNT=/mnt/efs
        mkdir -p "$EFSMNT" "$SHAREDIR"
        for((ii=0; ii < "${#HOSTS[*]}"; ii++)); do
            NFS_TYPE=${TYPES[$ii]}
            NFSHOST=${HOSTS[$ii]}
            NFS_OPTS=${OPTS[$ii]}
            NFSROOT=''
            if [[ ${NFSHOST} =~ ^([0-9\.]+)$ ]] || [[ $NFS_TYPE =~ nfs ]]; then
                NFSROOT=':/'
            fi

            if [[ $NFS_OPTS =~ accesspoint ]]; then
                if mount -t $NFS_TYPE -o "${NFS_OPTS},timeo=30" "${NFSHOST}:/" "${SHAREDIR}"; then
                    sed -i '/ myefs$/d' /etc/fstab
                    echo "${NFSHOST}:/ ${SHAREDIR}  $NFS_TYPE    ${NFS_OPTS},timeo=600,_netdev   0   0   # myefs" >> /etc/fstab
                    mount -o remount "$SHAREDIR" && break
                fi
            elif mount -t $NFS_TYPE -o "${NFS_OPTS},timeo=30" "${NFSHOST}${NFSROOT}" $EFSMNT; then
                if ! test -d "$EFSMNT"/cluster/${CLUSTER_NAME}; then
                    xmkdir -m 0755 -p "$EFSMNT"/cluster/${CLUSTER_NAME} || continue
                fi
                if mount -t $NFS_TYPE -o "${NFS_OPTS},timeo=30" "${NFSHOST}:/cluster/${CLUSTER_NAME}" "${SHAREDIR}"; then
                    sed -i '/ myefs$/d' /etc/fstab
                    echo "${NFSHOST}:/cluster/${CLUSTER_NAME} ${SHAREDIR}  $NFS_TYPE    ${NFS_OPTS},timeo=600,_netdev   0   0   # myefs" >> /etc/fstab
                fi
                mount -o remount "$SHAREDIR" && break
            fi
            mountpoint -q "$SHAREDIR" && break
        done
        if mountpoint -q "$SHAREDIR"; then
            MOUNT_OK=true
        fi

        if [ -n "$NFSMOUNT" ]; then
            if [ -z "$NFSHOST" ]; then
                NFSHOST="${NFSMOUNT%%:*}"
            fi
            NFSDIR="${NFSMOUNT#$NFSHOST}"
            NFSDIR="${NFSDIR#:}"
            NFSDIR="${NFSDIR#/}"
        fi

        XCE_LICENSE=/etc/xcalar/XcalarLic.key
        # shellcheck disable=SC2002
        (
        set -o pipefail
        set +x
        if [ ! -s "$XCE_LICENSE" ] && [ -n "$LICENSE" ]; then
            if [[ $LICENSE =~ ^s3:// ]]; then
                aws s3 cp $LICENSE - | base64 -d | gzip -dc > $XCE_LICENSE.tmp
            elif [[ $LICENSE =~ ^https:// ]]; then
                curl -fsSL "$LICENSE" | base64 -d | gzip -dc > $XCE_LICENSE.tmp
            elif [[ $LICENSE =~ ^file:// ]]; then
                cat "${LICENSE#file://}" | base64 -d | gzip -dc > $XCE_LICENSE.tmp
            else
                echo "$LICENSE" | base64 -d | gzip -dc > $XCE_LICENSE.tmp
            fi
            if [ ${PIPESTATUS[2]} -ne 0 ]; then
                echo >&2 "ERROR: Failed to decode license"
                truncate -s 0 $XCE_LICENSE
            fi
            touch $XCE_LICENSE
            chown xcalar:xcalar $XCE_LICENSE
            chmod 0600 $XCE_LICENSE
        fi
        )
        MOUNT_OK=false
        XLRROOT=/var/opt/xcalar
        if mountpoint -q "$SHAREDIR"; then
            XLRROOT=$SHAREDIR
            MOUNT_OK=true
        elif [ -n "$NFSMOUNT" ]; then
            mkdir -p $SHAREDIR
            if [ -n "$EFSAP" ]; then
                mount_xlrroot "${NFSHOST}:" $SHAREDIR
            else
                mount_xlrroot $NFSHOST:/${NFSDIR:-cluster/$CLUSTER_NAME} $SHAREDIR
            fi
            if  [ $? -eq 0 ]; then
                MOUNT_OK=true
                XLRROOT=$SHAREDIR
            else
                rmdir $SHAREDIR
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

        if test -e /etc/xcalar/Caddyfile; then
            if ! test -L /etc/xcalar/Caddyfile; then
                cp -n /etc/xcalar/Caddyfile /etc/xcalar/Caddyfile.orig
            fi
        fi
        if [ -n "$HOSTEDZONENAME" ] && [ -n "$CNAME" ]; then
            FQDN="${CNAME}.${HOSTEDZONENAME}"
        else
            FQDN="$(hostname -f)"
        fi

        XCE_USER_HOME=${XCE_USER_HOME:-/home/xcalar}
        SSHDIR=$XCE_USER_HOME/.ssh
        mkdir -p $SSHDIR
        chmod 0700 $SSHDIR
        touch $SSHDIR/config $SSHDIR/authorized_keys
        touch ${XCE_USER_HOME}/.hushlogin
        chmod 0600 ${SSHDIR}/authorized_keys ${SSHDIR}/config
        chown xcalar:xcalar $XCE_USER_HOME $SSHDIR ${SSHDIR}/* ${XCE_USER_HOME}/.hushlogin
    fi # CONFIG_ONLY
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
                TAG_VALUE="$ClusterName"
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
        if [ -n "$ClusterName" ]; then
            TAG_KEY=ClusterName
            TAG_VALUE="$ClusterName"
        elif [ -n "$AWS_AUTOSCALING_GROUPNAME" ]; then
            TAG_KEY=aws:autoscaling:groupName
            TAG_VALUE=$AWS_AUTOSCALING_GROUPNAME
        elif [ -n "$AWS_CLOUDFORMATION_STACK_NAME" ]; then
            TAG_KEY=aws:cloudformation:stack-name
            TAG_VALUE=$AWS_CLOUDFORMATION_STACK_NAME
        elif [ -n "$NAME" ]; then
            TAG_KEY=Name
            TAG_VALUE=$NAME
        else
            log "No valid tags found"
        fi
    fi

    if [ -n "$TAG_KEY" ] && [ -n "$TAG_VALUE" ]; then
        IPS=($(ec2_find_cluster "$TAG_KEY" "$TAG_VALUE"))
        NUM_INSTANCES="${#IPS[@]}"
        while [ $NUM_INSTANCES -lt $DESIRED ]; do
            log "Found $NUM_INSTANCES (DESIRED=$DESIRED) cluster members!"
            sleep 1
            if IPS=($(ec2_find_cluster "$TAG_KEY" "$TAG_VALUE")); then
                NUM_INSTANCES="${#IPS[@]}"
            fi
            DESIRED=$(asg_capacity "$AWS_AUTOSCALING_GROUPNAME")
        done
        : > /etc/ssh/ssh_known_hosts
        : > /etc/ansible/hosts
        MYNODE_ID=''
        if DNSDOMAIN=$(dnsdomainname); then
            DNSDOMAIN=".${DNSDOMAIN}"
        fi
        for NODE_ID in $(seq 0 $((NUM_INSTANCES - 1))); do
            local localip="${IPS[$NODE_ID]}"
            local localdns=ip-"${localip//./-}"
            local localfqdn="$localdns${DNSDOMAIN}"
            if [ "$LOCAL_IPV4" = "$localip" ]; then
                MYNODE_ID="${MYNODE_ID:-$NODE_ID}"
                echo "vm${NODE_ID}      ansible_connection=local" >> /etc/ansible/hosts
            else
                echo "vm${NODE_ID}      ansible_host=$localip" >> /etc/ansible/hosts
            fi
            sed -i "/$localip/d; /vm${NODE_ID}/d; /$localdns/d" /etc/hosts
            echo "$localip   $localfqdn $localdns vm${NODE_ID}" >> /etc/hosts
            ssh-keyscan $localip  ${localfqdn},${localdns},vm${NODE_ID} >> /etc/ssh/ssh_known_hosts
        done
        NODE_ID="${MYNODE_ID}"
        if [ "$LOCAL_IPV4" != "${IPS[$NODE_ID]}" ]; then
            log "WARNING: Unable to find $LOCAL_IPV4 in the list of IPS: ${IPS[*]}"
        fi
    else
        IPS=("$LOCAL_IPV4")
        NUM_INSTANCES=1
        MY_NODEID=0
        NODE_ID=$MY_NODEID
        echo "vm0   ansible_connection=local" > /etc/ansible/hosts
        echo "$LOCAL_IPV4   $(hostname -f) $(hostname -s) vm0" >> /etc/hosts
    fi
    if [ "$SCALE_IN_PROTECTION" = 1 ]; then
        if [ $NODE_ID -ge $DESIRED ]; then
            aws autoscaling set-instance-protection --instance-ids "$INSTANCE_ID" --auto-scaling-group-name "$AWS_AUTOSCALING_GROUPNAME" --no-protected-from-scale-in || true
        else
            aws autoscaling set-instance-protection --instance-ids "$INSTANCE_ID" --auto-scaling-group-name "$AWS_AUTOSCALING_GROUPNAME" --protected-from-scale-in || true
        fi
    fi

    aws ec2 create-tags --resources $INSTANCE_ID \
        --tags Key=Name,Value="${AWS_CLOUDFORMATION_STACK_NAME}-${NODE_ID}" \
               Key=Node_ID,Value="${NODE_ID}"

    if [ $NODE_ID -ge $DESIRED ]; then
        shutdown_node
        exit 0
    fi
    if [ $NODE_ID -eq 0 ]; then
        if [ -n "$NIC" ]; then
            ec2_attach_nic "$NIC" "$INSTANCE_ID"
        fi
        if ((CONFIG_ONLY)); then
            :
        else
            if ((PUBLICIP)); then
                if [ -n "$NIC" ]; then
                    DNS_AND_IP="$(aws ec2 describe-network-interfaces --network-interface-ids $NIC --query 'NetworkInterfaces[].Association.[PublicDnsName,PublicIp]' --output text)"
                else
                    DNS_AND_IP="$(imds /meta-data/public-hostname) $(imds /meta-data/public-ipv4)"
                fi
            else
                DNS_AND_IP="$(imds /meta-data/local-hostname) $(imds /meta-data/private-ipv4)"
            fi

            test -d $XLRROOT/config || mkdir -p $XLRROOT/config
            if file_size $SSLCRTFILE 10 && file_size $SSLKEYFILE 10; then
                CRT_KEY=($XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.crt $XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.key)
                fix_multiline_cert < $SSLCRTFILE > "${CRT_KEY[0]}"
                fix_multiline_cert < $SSLKEYFILE > "${CRT_KEY[1]}"
                if ! verify_ssl "${CRT_KEY[@]}"; then
                    rm -f "${CRT_KEY[@]}"
                    CRT_KEY=($(cd $XLRROOT/config && generate_ssl $DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
                fi
            else
                CRT_KEY=($(cd $XLRROOT/config && generate_ssl $DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
            fi
            if test -e ${CRT_KEY[0]} && test -e ${CRT_KEY[1]}; then
                chown xcalar:xcalar "${CRT_KEY[@]}"
                chmod 0644 "${CRT_KEY[0]}"
                chmod 0600 "${CRT_KEY[1]}"
                generate_caddy /etc/xcalar/Caddyfile.orig "${CRT_KEY[@]}" > $XLRROOT/config/Caddyfile.$$
            else
                generate_caddy /etc/xcalar/Caddyfile.orig > $XLRROOT/config/Caddyfile.$$
            fi
            if ! test -e ${XLRROOT}/config/id_rsa; then
                ssh-keygen -t rsa -N "" -q -f ${XLRROOT}/config/id_rsa -C "xcalar@ec2"
                chown xcalar:xcalar ${SSHDIR}/id_rsa.pub
            fi
            mv $XLRROOT/config/Caddyfile.$$ $XLRROOT/config/Caddyfile
            (
            set +x 2>/dev/null
            unset PS4
            umask 002
            mkdir -p /run/xcalar
            chmod 2770 /run/xcalar
            chown root:xcalar /run/xcalar
            tmpdir=$(mktemp -d /run/xcalar/XXXXXX)
            tmpfile="$tmpdir"/secret
            if [ -n "$SECRETID" ]; then
                set -o pipefail
                for((ii=0; ii<2; ii++)); do
                    if aws secretsmanager get-secret-value --secret-id "$SECRETID" --version-stage "AWSCURRENT" | jq -r '.SecretString' > "${tmpfile}.tmp"; then
                        mv "${tmpfile}.tmp" "${tmpfile}.sec"
                        break
                    fi
                    sleep 1
                done
            fi
            if test -e "${tmpfile}.sec"; then
                PASS="$(jq -r '.password' < ${tmpfile}.sec)"
            elif test -n "$ADMIN_PASSWORD"; then
                PASS="$ADMIN_PASSWORD"
            elif test -e "$ADMIN_PASSWORD_FILE"; then
                PASS="$(cat $ADMIN_PASSWORD_FILE)"
            else
                PASS="$(openssl rand 12 | base64 -w0)"
                echo "*****************************" >&2
                echo "Generated Xcalar Login Password: $PASS" >&2
                echo "*****************************" >&2
                echo "$PASS" > /etc/xcalar/admin_password
                chmod 0640 /etc/xcalar/admin_password
                chown root:xcalar /etc/xcalar/admin_password
            fi

            if /opt/xcalar/scripts/genDefaultAdmin.sh \
                  --username "${ADMIN_USERNAME:-xdpadmin}" \
                  --email "${ADMIN_EMAIL:-nobody@xcalar.com}" \
                  --password  "$PASS" > ${tmpfile}.json; then
                    mv ${tmpfile}.json $XLRROOT/config/defaultAdmin.json
            fi
            rm -rf $(dirname $tmpfile)
            )
            chmod 0700 $XLRROOT/config
            chmod 0600 $XLRROOT/config/defaultAdmin.json $XLRROOT/config/*.key
            chown xcalar:xcalar $XLRROOT/config $XLRROOT/config/*

            PYSITE=$(cat $PTHFILE 2> /dev/null || echo $XLRROOT/pysite)
            mkdir -p $PYSITE
            if ! test -e $PTHFILE; then
                echo $PYSITE > $PTHFILE
            fi
            chown xcalar:xcalar $PYSITE
            REQ=$XLRROOT/config/requirements.txt
            CON=$(ls $PREFIX/share/doc/*python*/requirements.txt 2>/dev/null)
            if [ $? -eq 0 ] && test -e "$REQ" && test -e "$CON"; then
                VENV=$(mktemp -d -t venv.XXXXXX)
                pyvenv $VENV $PREFIX/bin/python3
                $VENV/bin/python -m pip install -t "$PYSITE" -r "$REQ" -c "$CON"
            fi
        fi

        ln -sfn $XLRROOT/config/Caddyfile /etc/xcalar/Caddyfile

        if ! mountpoint -q $EPHEMERAL; then
            mkdir -p -m 1777 $EPHEMERAL
            if cloud-init-per instance ephemeral-init /bin/bash -x /usr/bin/ephemeral-init.sh; then
                echo "Ok!"
            fi
        fi
        sed -i '/ephemeral-disk/d' /etc/systemd/system/xcalar.service.d/ephemeral.conf
    fi # NODE_0

    if ((CONFIG_ONLY)); then
        TMP=$(mktemp -t xce.XXXXXX)
        /opt/xcalar/scripts/genConfig.sh $XCE_CONFIG - "${IPS[@]}" > $TMP
        mv $TMP $XCE_CONFIG
    else
        if mountpoint -q "$EPHEMERAL"; then
            XCE_XDBSERDESPATH=${EPHEMERAL}/xcalar/serdes
            XCE_EPHEMERALDIRS="${XCE_XDBSERDESPATH} ${EPHEMERAL}/xcalar/bc ${EPHEMERAL}/xcalar/stats"

            xmkdir -p $XCE_XDBSERDESPATH
            xmkdir -p ${EPHEMERAL}/xcalar/bc
            xmkdir -p ${EPHEMERAL}/xcalar/stats

            #mkdir -m 1777 -p $XCE_EPHEMERALDIRS
            #chown xcalar:xcalar $XCE_EPHEMERALDIRS
            #chmod 0755 $XCE_EPHEMERALDIRS

            XCE_XDBSERDESMB=$(($(mbfree $XCE_XDBSERDESPATH) - 1000))
            if [[ $XCE_XDBSERDESMB -gt 0 ]]; then
                XDB_SERDESMODE=2
            fi
        fi

        mkdir -m 0700 -p /home/xcalar/.ssh
        cat $XLRROOT/config/id_rsa.pub >> /home/xcalar/.ssh/authorized_keys
        chown -R xcalar:xcalar /home/xcalar/.ssh
        chmod 0700 /home/xcalar/.ssh
        chmod 0600 /home/xcalar/.ssh/authorized_keys

        (
        echo "Constants.SendSupportBundle=$SENDSUPPORT"
        echo "Constants.XcalarLogCompletePath=/var/log/xcalar"
        /opt/xcalar/scripts/genConfig.sh ${XCE_TEMPLATE} - "${IPS[@]}"
        if [ -n "$XDB_SERDESMODE" ]; then
            echo "Constants.XdbSerDesMode=${XDB_SERDESMODE}"
            echo "Constants.XdbLocalSerDesPath=$XCE_XDBSERDESPATH"
            echo "Constants.XcalarStatsPath=${EPHEMERAL}/xcalar/stats"
            echo "Constants.BufferCachePath=${EPHEMERAL}/xcalar/bc"
        fi
        if [ -n "$XCE_XDBSERDESMB" ]; then
            echo "Constants.XdbSerDesMaxDiskMB=${XCE_XDBSERDESMB}"
        fi
        echo "Constants.XcalarRootCompletePath=$XLRROOT"
        ) | sed -e 's@^Constants.XcalarRootCompletePath.*$@Constants.XcalarRootCompletePath='$XLRROOT'@' > "$XCE_CONFIG"
    fi

    if [ "$BOOTCMD" = stop ] || [ "$BOOTCMD" = restart ]; then
        log "Stopping Xcalar"
        systemctl stop $SYSTEMD_UNIT
        rc=$?
        log "Waiting for Xcalar ... "
        systemd_wait_xcalar 120
        if [ "$BOOTCMD" = stop ]; then
            return $rc
        fi
    fi
    log "Starting Xcalar"

    copysshkeys

    systemctl daemon-reload
    systemctl start $SYSTEMD_UNIT
    rc=$?
    systemctl enable $SYSTEMD_UNIT
    cat $XLRROOT/config/authorized_keys > ${SSHDIR}/.authorized_keys

    log "All done with user-data.sh (rc=$rc)"
    log "===> Ending at $(date +'%F%T%Tz')"
    return $rc
}

main "$@"
exit $?
