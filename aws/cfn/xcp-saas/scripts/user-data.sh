#!/bin/bash
#
# shellcheck disable=SC2086,SC2304,SC2034,SC2206,SC2207,SC2046,SC2155,SC2129

echo >&2 "Starting user-data.sh"

set -x
LOGFILE=/var/log/user-data.log
touch $LOGFILE
chmod 0600 $LOGFILE
if [ -t 1 ]; then
    :
else
    exec > >(tee -a $LOGFILE | logger -t user-data -s 2>/dev/console) 2>&1
fi
start=($(date +'%s %N'))

log() {
    local dt=$(dt)
    logger --id -p "local0.info" -t user-data -s dt="${dt}" "$@"
}

dt() {
    local now=($(date +'%s %N'))
    local dt=$((now[0] - start[0]))
    local dn=$((now[1] - start[1]))
    if [ $dn -lt 0 ]; then
        dn=$((1000000000 + dn))
        dt=$((dt - 1))
    fi
    printf '%d.%.9d\n' ${dt} ${dn}
}

# Instance meta-data service v2
imds() {
    IMDSV2=latest
    if [ -z "$IMDSV2_TOKEN" ]; then
        IMDSV2_TOKEN=$(curl -s -X PUT "http://169.254.169.254/$IMDSV2/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    fi
    curl -s -H "X-aws-metadata-token: $IMDSV2_TOKEN" "http://169.254.169.254/$IMDSV2/${1#/}"
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
        --auto-scaling-group-names "$1" --query 'AutoScalingGroups[][MinSize,MaxSize,DesiredCapacity]' --output text
}

expserver_config() {
    if [ -n "$AUTH_STACK_NAME" ]; then
        XCE_EXPSERVER_CLOUD_AUTH_CONFIG="$(aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/auth/${AUTH_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^"//' -e 's/"$//' -e 's/\\\\n/\\n/g')"
        sed --follow-symlinks -i '/^## Xcalar Cloud Auth Start/,/## Xcalar Cloud Auth End/d' /etc/default/xcalar

        echo '## Xcalar Cloud Auth Start' >>/etc/default/xcalar
        printf "$XCE_EXPSERVER_CLOUD_AUTH_CONFIG" >>/etc/default/xcalar
        echo '## Xcalar Cloud Auth End' >>/etc/default/xcalar
    fi
    if [ -n "$MAIN_STACK_NAME" ]; then
        XCE_EXPSERVER_CLOUD_MAIN_CONFIG="$(aws ssm get-parameter --region ${AWS_REGION} --name "/xcalar/cloud/main/${MAIN_STACK_NAME}" --query "Parameter.Value" | sed -e 's/^"//' -e 's/"$//' -e 's/\\\\n/\\n/g')"
        sed --follow-symlinks -i '/^## Xcalar Cloud Main Start/,/## Xcalar Cloud Main End/d' /etc/default/xcalar

        echo '## Xcalar Cloud Main Start' >>/etc/default/xcalar
        printf "$XCE_EXPSERVER_CLOUD_MAIN_CONFIG" >>/etc/default/xcalar
        echo '## Xcalar Cloud Main End' >>/etc/default/xcalar
    fi
    printf "JWT_SECRET=xcalarSsssh" >>/etc/default/xcalar
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
ssm_get_string() {
    aws ssm get-parameter --query 'Parameter.Value' --output text --name "$@"
}

ssm_get_secret() {
    aws ssm get-parameter --query 'Parameter.Value' --output text --with-decryption --name "$@"
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
    if existing_mount="$(
        set -o pipefail
        findmnt -nT "$2" | awk '{print $2}'
    )"; then
        if [ "$existing_mount" == "$1" ]; then
            log "$1 already mounted to $2"
            return 0
        fi
    fi

    # shellcheck disable=SC2046
    set +e
    local rc tmpdir
    tmpdir="$(mktemp -d -t nfs.XXXXXX)"
    mount -t $NFS_TYPE -o ${NFS_OPTS},timeo=3 $NFSHOST:/$NFSDIR $tmpdir
    rc=$?
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
        echo "${NFSHOST}:/${NFSDIR} $MOUNT $NFS_TYPE  $NFS_OPTS 0 0" >>/etc/fstab
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
        if [[ $eni_status == available ]]; then
            if aws ec2 attach-network-interface --network-interface-id ${nic} --instance-id ${instance_id} --device-index 1; then
                log "ENI $nic attached to $instance_id"
                break
            fi
        fi
        eni_instance=$(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[].Attachment.InstanceId' --network-interface-ids ${nic} --output text)
        if [[ $eni_instance == "$instance_id" ]]; then
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
        cat <<EOF
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
O = Temporary Example CA
OU = Please Replace
emailAddress = fake@example.com
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
IP.3 = ${public_ip}
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
    ); then
        echo >&2 "Failed to generate OpenSSL cert. See $tmp"
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
        if /etc/ssl/certs/make-dummy-cert $certname >/dev/null; then
            sed -n '/---BEGIN CERT/,/---END CERT/p' $certname >$crt
            sed -n '/---BEGIN PRIVATE/,/---END PRIVATE/p' $certname >$key
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

pyver() {
    $1 -c 'from __future__ import print_function; import sys; vi=sys.version_info; print("{}.{}".format(vi.major,vi.minor)'
}

pyvenv() {
    local venv="$1" python="${2:-$PREFIX/bin/python3}"

    ver=$(pyver $python)
    export PIP_FIND_LINKS=/var/lib/wheels-${pyver}

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

node_0() {
    if [ -n "$NIC" ]; then
        while true; do
            eni_status=$(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[].Status' --network-interface-ids ${NIC} --output text)
            if [[ $eni_status == available ]]; then
                if aws ec2 attach-network-interface --network-interface-id ${NIC} --instance-id ${INSTANCE_ID} --device-index 1; then
                    echo >&2 "ENI $NIC attached to $INSTANCE_ID"
                    break
                fi
            fi
            eni_instance=$(aws ec2 describe-network-interfaces --query 'NetworkInterfaces[].Attachment.InstanceId' --network-interface-ids ${NIC} --output text)
            if [[ $eni_instance == "$INSTANCE_ID" ]]; then
                echo >&2 "ENI $NIC already attached"
                break
            fi
            echo >&2 "Waiting for ENI $NIC that is $eni_status by $eni_instance .."
            sleep 10
        done
    fi
    if ! test -d ${XLRROOT}/jupyterNotebooks; then
        rsync -avzr /var/opt/xcalar/ ${XLRROOT}/
    fi

    test -d $XLRROOT/config || mkdir -p $XLRROOT/config
    (
        # We don't want the sensitive parts in the log
        set +x
        if [ -n "${ADMIN_USERNAME}" ] && [ -n "${ADMIN_PASSWORD}" ]; then
            /opt/xcalar/scripts/genDefaultAdmin.sh \
                --username "${ADMIN_USERNAME}" \
                --email "${ADMIN_EMAIL:-info@xcalar.com}" \
                --password "${ADMIN_PASSWORD}" >/tmp/defaultAdmin.json \
                && mv /tmp/defaultAdmin.json $XLRROOT/config/defaultAdmin.json
        fi
        chmod 0700 $XLRROOT/config
        chmod 0600 $XLRROOT/config/defaultAdmin.json
        if [ -n "$CERTSTORE" ]; then
            CERTDIR=$XLRROOT/.cert
            CERT=$CERTDIR/xcalar.crt
            KEY=$CERTDIR/xcalar.key
            mkdir -p -m 0700 $CERTDIR
            get_ssm_x509 "$CERTSTORE" "$CRT" "$KEY"
        fi
    )
    if [[ $SHARED_CONFIG == true ]]; then
        mv $XCE_CONFIG $XLRROOT/default.cfg
    fi

    chown -R xcalar:xcalar $XLRROOT/
    pidof caddy >/dev/null && kill -USR1 $(pidof caddy) || true
}

get_ssm_x509() {
    local CERTSTORE="$1" CRT="$2" KEY="$3"

    if [ -n "$CERTSTORE" ]; then
        ssm_get_secret "${CERTSTORE}.crt" | base64 -d | gzip -dc >$CRT \
            && ssm_get_secret "${CERTSTORE}.key" | base64 -d | gzip -dc >$KEY \
            && chmod 0644 $CRT \
            && chmod 0640 $KEY \
            && chown root:xcalar $CRT $KEY
        return $?
    fi
    return 1
}

osid_init() {
    RELEASE_NAME=$(rpm -qf /etc/system-release --qf '%{NAME}')
    RELEASE_VERSION=$(rpm -qf /etc/system-release --qf '%{VERSION}')
    case "$RELEASE_VERSION" in
        6 | 6*)
            OSID=el6
            INIT=sysvinit
            SYSTEMD=0
            ;;
        7 | 7*)
            OSID=el7
            INIT=systemd
            SYSTEMD=1
            ;;
        201*)
            OSID=amzn1
            INIT=sysvinit
            SYSTEMD=0
            ;;
        2)
            OSID=amzn2
            INIT=systemd
            SYSTEMD=1
            ;;
        *)
            log "ERROR: Unknown OS version $RELEASE_VERSION"
            exit 1
            ;;
    esac
}

main() {
    eval $(ec2-tags -s -i)
    mkdir -p /var/tmp/xcalar-root
    chown xcalar:xcalar /var/tmp/xcalar-root
    osid_init

    # shellcheck disable=SC2046
    ENV_FILE=/var/lib/cloud/instance/ec2.env
    CLOUD_ENV_FILE=/var/lib/cloud/instance/cloud.env

    set -a
    if [ -e "$ENV_FILE" ]; then
        . $ENV_FILE
    fi

    if [ -e "$CLOUD_ENV_FILE" ]; then
        . $CLOUD_ENV_FILE
    fi
    set +a

    set +x
    PREFIX=${PREFIX:-/opt/xcalar}
    SSLKEYFILE=${SSLKEYFILE:-/etc/xcalar/xcalar.key}
    SSLCRTFILE=${SSLCRTFILE:-/etc/xcalar/xcalar.crt}
    SITE_DIR=$($PREFIX/bin/python3 -c 'import site; print(site.getsitepackages()[-1])')
    PTHFILE=${SITE_DIR}/mnt-xcalar-pysite.pth

    while [ $# -gt 0 ]; do
        cmd="$1"
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
            --certstore)
                CERTSTORE="$1"
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
                if [ -n "$1" ]; then
                    SSLCRT="$1"
                    echo "$1" >$SSLCRTFILE
                    chown root:xcalar $SSLCRTFILE
                    chmod 0644 $SSLCRTFILE
                fi
                shift
                ;;
            --ssl-key)
                if [ -n "$1" ]; then
                    SSLKEY="$1"
                    echo "$1" >$SSLKEYFILE
                    chown xcalar:xcalar $SSLKEYFILE
                    chmod 0600 $SSLKEYFILE
                fi
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
    set -x

    CLUSTER_SIZE=${CLUSTER_SIZE:-1}
    XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
    XCE_TEMPLATE=${XCE_TEMPLATE:-/etc/xcalar/template.cfg}
    EPHEMERAL=/ephemeral/data

    INSTANCE_ID=$(imds /meta-data/instance-id)
    AVZONE=$(imds /meta-data/placement/availability-zone)
    INSTANCE_TYPE=$(imds /meta-data/instance-type)
    LOCAL_IPV4=$(imds /meta-data/local-ipv4)
    LOCAL_HOSTNAME=$(imds /meta-data/local-hostname)
    sed -i "/^${LOCAL_IPV4}/d; /${LOCAL_HOSTNAME}/d;" /etc/hosts
    echo "$LOCAL_IPV4	$LOCAL_HOSTNAME     $(hostname -s)" | tee -a /etc/hosts

    export AWS_DEFAULT_REGION="${AVZONE%[a-f]}"
    export AWS_REGION=${AWS_REGION:-$AWS_DEFAULT_REGION}

    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin:/opt/mssql-tools/bin:$PREFIX/bin
    echo "export PATH=$PATH" >/etc/profile.d/path.sh

    NFSHOST="${NFSMOUNT%%:*}"
    NFSDIR="${NFSMOUNT#$NFSHOST}"
    NFSDIR="${NFSDIR#:}"
    NFSDIR="${NFSDIR#/}"

    if [ -z "$NFS_TYPE" ]; then
        if [[ $NFSHOST =~ ^fs-[0-9a-f]{8}$ ]]; then
            FSID="$NFSHOST"
            if [ -n "$SUBNET" ]; then
                if EFSIP="$(efsip $NFSHOST $SUBNET)"; then
                    NFSHOST=$EFSIP
                    NFS_TYPE=nfs
                    NFS_OPTS="nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport"
                fi
            else
                yum install -y amazon-efs-utils
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
            aws s3 cp $LICENSE - | base64 -d | gzip -dc >$XCE_LICENSE
        elif [[ $LICENSE =~ ^https:// ]]; then
            curl -fsSL "$LICENSE" | base64 -d | gzip -dc >$XCE_LICENSE
        else
            echo "$LICENSE" | base64 -d | gzip -dc >$XCE_LICENSE
        fi
        if [ ${PIPESTATUS[2]} -ne 0 ]; then
            echo "ERROR: Failed to decode license"
            truncate -s 0 $XCE_LICENSE
        fi
        #touch $XCE_LICENSE
        #chown xcalar:xcalar $XCE_LICENSE
        #2chmod 0600 $XCE_LICENSE
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
        if [ -n "$CLUSTERNAME" ]; then
            TAG_KEY=ClusterName
            TAG_VALUE="$CLUSTERNAME"
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
        : >/etc/ssh/ssh_known_hosts
        : >/etc/ansible/hosts
        MYNODE_ID=''
        for NODE_ID in $(seq 0 $((NUM_INSTANCES - 1))); do
            local localip="${IPS[$NODE_ID]}"
            local localdns=ip-"${localip//./-}"
            local localfqdn="$localdns.$(dnsdomainname)"
            if [ "$LOCAL_IPV4" == "$localip" ]; then
                MYNODE_ID="${MYNODE_ID:-$NODE_ID}"
                echo "vm${NODE_ID}      ansible_connection=local" >>/etc/ansible/hosts
            else
                echo "vm${NODE_ID}      ansible_host=$localip" >>/etc/ansible/hosts
            fi
            sed -i "/$localip/d; /vm${NODE_ID}/d; /$localdns/d" /etc/hosts
            echo "$localip   $localfqdn $localdns vm${NODE_ID}" >>/etc/hosts
            for ii in $localip $localfqdn $localdns vm${NODE_ID}; do
                echo "Scanning $ii" >&2
                ssh-keyscan $ii >>/etc/ssh/ssh_known_hosts
            done
        done
        NODE_ID="${MYNODE_ID}"
        if [ "$LOCAL_IPV4" != "${IPS[$NODE_ID]}" ]; then
            log "WARNING: Unable to find $LOCAL_IPV4 in the list of IPS: ${IPS[*]}"
        fi
    else
        IPS=("$LOCAL_IPV4")
        NODE_ID=0
        echo "vm0   ansible_connection=local" >/etc/ansible/hosts
        echo "$LOCAL_IPV4   $(hostname -f) $(hostname -s) vm0" >>/etc/hosts
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
    sed -i "4i Constants.SendSupportBundle=true" $XCE_TEMPLATE
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
    if [ -n "$HOSTEDZONENAME" ] && [ -n "$CNAME" ]; then
        FQDN="${CNAME}.${HOSTEDZONENAME}"
    else
        FQDN="$(hostname -f)"
    fi

    XCE_USER_HOME=${XCE_USER_HOME:-/home/xcalar}
    SSHDIR=$XCE_USER_HOME/.ssh
    mkdir -p $SSHDIR
    chmod 0700 $SSHDIR
    touch ${XCE_USER_HOME}/.hushlogin
    chown xcalar:xcalar $SSHDIR ${XCE_USER_HOME}/.hushlogin
    if [ $NODE_ID -eq 0 ]; then
        log "Start ec2_attach_nic"
        if [ -n "$NIC" ]; then
            ec2_attach_nic "$NIC" "$INSTANCE_ID"
            PUBLIC_DNS_AND_IP="$(aws ec2 describe-network-interfaces --network-interface-ids $NIC --query 'NetworkInterfaces[].Association.[PublicDnsName,PublicIp]' --output text)"
        else
            PUBLIC_DNS_AND_IP="$(imds /meta-data/public-hostname) $(imds /meta-data/public-ipv4)"
        fi
        log "End ec2_attach_nic"
        log "Start SSL"
        test -d $XLRROOT/config || mkdir -p $XLRROOT/config
        if ! verify_ssl "$SSLCRTFILE" "$SSLKEYFILE"; then
            log "Checking SSM $CERTSTORE for X509"
            if get_ssm_x509 "$CERTSTORE" "$SSLCRTFILE" "$SSLKEYFILE"; then
                log "Got certs from SSM"
            else
                log "Failed to get certs from SSM"
            fi
        fi
        if file_size $SSLCRTFILE 10 && file_size $SSLKEYFILE 10; then
            CRT_KEY=($XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.crt $XLRROOT/config/${AWS_CLOUDFORMATION_STACK_NAME}.key)
            fix_multiline_cert <$SSLCRTFILE >"${CRT_KEY[0]}"
            fix_multiline_cert <$SSLKEYFILE >"${CRT_KEY[1]}"
            if ! verify_ssl "${CRT_KEY[@]}"; then
                rm -f "${CRT_KEY[@]}"
                CRT_KEY=($(cd $XLRROOT/config && generate_ssl $PUBLIC_DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
            fi
        else
            CRT_KEY=($(cd $XLRROOT/config && generate_ssl $PUBLIC_DNS_AND_IP $AWS_CLOUDFORMATION_STACK_NAME))
        fi
        if test -e ${CRT_KEY[0]} && test -e ${CRT_KEY[1]}; then
            chown xcalar:xcalar "${CRT_KEY[@]}"
            chmod 0644 "${CRT_KEY[0]}"
            chmod 0600 "${CRT_KEY[1]}"
            generate_caddy /etc/xcalar/Caddyfile.orig "${CRT_KEY[@]}" >$XLRROOT/config/Caddyfile.$$
        else
            generate_caddy /etc/xcalar/Caddyfile.orig >$XLRROOT/config/Caddyfile.$$
        fi
        log "End SSL"
        ssh-keygen -t rsa -N "" -f ${SSHDIR}/id_rsa -C "xcalar@$(hostname -f)"
        chown xcalar:xcalar ${SSHDIR}/id_rsa.pub
        cp -a ${SSHDIR}/id_rsa.pub $XLRROOT/config/authorized_keys
        chmod 0600 $XLRROOT/config/authorized_keys
        mv $XLRROOT/config/Caddyfile.$$ $XLRROOT/config/Caddyfile
        /opt/xcalar/scripts/genDefaultAdmin.sh \
            --username "${ADMIN_USERNAME}" \
            --email "${ADMIN_EMAIL:-info@xcalar.com}" \
            --password "${ADMIN_PASSWORD}" >/tmp/defaultAdmin.json \
            && mv /tmp/defaultAdmin.json $XLRROOT/config/defaultAdmin.json
        chmod 0700 $XLRROOT/config
        chmod 0600 $XLRROOT/config/defaultAdmin.json $XLRROOT/config/*.key
        chown xcalar:xcalar $XLRROOT/config $XLRROOT/config/*

        PYSITE=$(cat $PTHFILE 2>/dev/null || echo $XLRROOT/pysite)
        mkdir -p $PYSITE
        if ! test -e $PTHFILE; then
            echo $PYSITE >$PTHFILE
        fi
        chown xcalar:xcalar $PYSITE
        REQ=$XLRROOT/config/requirements.txt
        CON=$PREFIX/share/doc/xcalar-python*/requirements.txt
        if test -e $XLRROOT/config/requirements.txt; then
            VENV=$(mktemp -d -t venv.XXXXXX)
            pyvenv $VENV $PREFIX/bin/python3
            $VENV/bin/python -m pip install -t $PYSITE -r $XLRROOT/config/requirements.txt -c $CON
        fi
    fi

    ln -sfn $XLRROOT/config/Caddyfile /etc/xcalar/Caddyfile
    log "Start wait for ephemeral"
    if rpm -q ephemeral-disk; then
        local dt=0
        until mountpoint -q $EPHEMERAL; do
            sleep 1
            dt=$((dt + 1))
            log "$dt Waiting for $EPHEMERAL ..."
            if [ $dt -gt 120 ]; then
                break
            fi
        done
    fi

    if mountpoint -q "$EPHEMERAL"; then
        XCE_XDBSERDESPATH=${XCE_XDBSERDESPATH:-${EPHEMERAL}/serdes}
    fi
    if [ ! -d "$XCE_XDBSERDESPATH" ]; then
        if ! mkdir -m 1777 "$XCE_XDBSERDESPATH"; then
            XCE_XDBSERDESPATH=''
        fi
    fi
    log "End wait for ephemeral"

    log "Start Xcalar Service"
    if [ -d "$XCE_XDBSERDESPATH" ]; then
        chown xcalar:xcalar "$XCE_XDBSERDESPATH"
        XCE_XDBSERDESMB=$(($(mbfree $XCE_XDBSERDESPATH) - 1000))
        if [[ $XCE_XDBSERDESMB -gt 0 ]]; then
            sed -i "4i Constants.XdbSerDesMode=2" $XCE_TEMPLATE
            sed -i "4i Constants.XdbLocalSerDesPath=$XCE_XDBSERDESPATH" $XCE_TEMPLATE
            sed -i "4i Constants.XdbSerDesMaxDiskMB=$XCE_XDBSERDESMB" $XCE_TEMPLATE
        fi
    fi

    /opt/xcalar/scripts/genConfig.sh ${XCE_TEMPLATE} - "${IPS[@]}" >$XCE_CONFIG

    expserver_config

    if test -e /lib/systemd/system/xcalar-services.target; then
        SYSTEMD_UNIT=xcalar-services.target
    else
        SYSTEMD_UNIT=xcalar.service
    fi

    if ((SYSTEMD)); then
        systemctl start $SYSTEMD_UNIT
    else
        /etc/init.d/xcalar start
    fi
    rc=$?
    log "End Xcalar Service ($rc)"

    cp -a $XLRROOT/config/authorized_keys $SSHDIR

    if ((SYSTEMD)); then
        systemctl enable $SYSTEMD_UNIT
    else
        chkconfig xcalar on
    fi

    log "All done with user-data.sh (rc=$rc)"

    collect_boot_metrics
    return $rc
}

collect_boot_metrics() {
    (
        cd /var/log
        cloud-init collect-logs
        mkdir -p cloud-init-logs
        tar zxvf cloud-init.tar.gz -C cloud-init-logs/ --strip=1
        rm -f cloud-init.tar.gz
        systemd-analyze plot >boot.svg
        systemd-analyze critical-chain >systemd-analyze-critical-chain.txt
        systemd-analyze blame >systemd-analyze-blame.txt
    )
}

main "$@"
