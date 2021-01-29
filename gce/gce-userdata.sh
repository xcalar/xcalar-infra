#!/bin/bash

command_exists() {
    command -v "$@" >/dev/null 2>&1
}

# Taken from GCloud's ubuntu package /usr/share/google/get_metadata_value
get_metadata_value() {
    if test -e /usr/share/google/get_metadata_value; then
        /usr/share/google/get_metadata_value "$1"
        return $?
    fi
    local readonly tmpfile=$(mktemp)
    http_code=$(curl -f "http://metadata.google.internal/computeMetadata/v1/instance/${1}" -H "Metadata-Flavor: Google" -w "%{http_code}" \
        -s -o ${tmpfile} 2>/dev/null)
    local readonly return_code=$?
    # If the command completed successfully, print the metadata value to stdout.
    if [[ ${return_code} == 0 && ${http_code} == 200 ]]; then
        cat ${tmpfile}
    fi
    rm -f ${tmpfile}
    return ${return_code}
}

# Safer curl. Use IPv4, add some retries, timeouts, and --location (aka, -L)
# to follow redirects is pretty much mandatory. We've seen curl try to use IPv6 on
# and many intermittent errors when retry isn't used. When a cluster comes up
# all the nodes tend to hit the source http server for the file, causing it to
# temporarily be unavailable.
safe_curl() {
    curl -4 --location --retry 20 --retry-delay 3 --retry-max-time 60 "$@"
}

os_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            rhel)
                ELVERSION=$VERSION_ID
                echo rhel${ELVERSION}
                ;;
            centos)
                ELVERSION=$VERSION_ID
                echo el${ELVERSION}
                ;;
            ubuntu)
                UBVERSION="$(echo $VERSION_ID | cut -d'.' -f1)"
                echo ub${UBVERSION}
                ;;
            *)
                echo >&2 "Unknown OS version: $PRETTY_NAME ($VERSION)"
                return 1
                ;;
        esac
    elif [ -e /etc/redhat-release ]; then
        ELVERSION="$(grep -Eow '([0-9\.]+)' /etc/redhat-release | cut -d'.' -f1)"
        if grep -q 'Red Hat' /etc/redhat-release; then
            echo rhel${ELVERSION}
        elif grep -q CentOS /etc/redhat-release; then
            echo el${ELVERSION}
        fi
    else
        echo >&2 "Unknown OS version"
        return 1
    fi
}

do_install() {

    user="$(id -un 2>/dev/null || true)"

    sh_c='sh -c'
    if [ "$user" != 'root' ]; then
        if command_exists sudo; then
            sh_c='sudo -E sh -c'
        elif command_exists su; then
            sh_c='su -c'
        else
            cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
            exit 1
        fi
    fi

    curl=''
    if command_exists curl; then
        curl='curl -sSL'
    elif command_exists wget; then
        curl='wget -qO-'
    elif command_exists busybox && busybox --list-modules | grep -q wget; then
        curl='busybox wget -qO-'
    fi

    os_version >/var/tmp/os_version
    case "$(os_version)" in
        rhel* | el*)
            $sh_c "yum remove -y xcalar xcalar-python27"
            gcsfuseRepo="/etc/yum.repos.d/gcsfuse.repo"
            if true; then
                $sh_c "rm -f $gcsfuseRepo"
            else
                $sh_c "touch $gcsfuseRepo"
                $sh_c "echo '[gcsfuse]' > $gcsfuseRepo"
                $sh_c "echo 'name=gcsfuse (packages.cloud.google.com)' >> $gcsfuseRepo"
                $sh_c "echo 'baseurl=https://packages.cloud.google.com/yum/repos/gcsfuse-el${ELVERSION}-x86_64' >> $gcsfuseRepo"
                $sh_c "echo 'enabled=1' >> $gcsfuseRepo"
                $sh_c "echo 'gpgcheck=1' >> $gcsfuseRepo"
                $sh_c "echo 'repo_gpgcheck=1' >> $gcsfuseRepo"
                $sh_c "echo 'gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpp' >> $gcsfuseRepo"
                $sh_c "echo '    https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg' >> $gcsfuseRepo"
            fi
            $sh_c 'yum remove -y epel-release'
            $sh_c 'yum clean all'
            $sh_c 'yum makecache fast'
            $sh_c 'yum install -y epel-release'
            $sh_c 'yum install -y nfs-utils curl epel-release collectd'
            $sh_c "yum localinstall -y http://repo.xcalar.net/deps/gcsfuse-0.20.1-1.x86_64.rpm"
            ;;
        ub*)
            $sh_c "apt-get remove -y xcalar xcalar-python27"
            export DEBIAN_FRONTEND=noninteractive
            $sh_c 'echo "deb http://packages.cloud.google.com/apt gcsfuse-`lsb_release -c -s` main" > /etc/apt/sources.list.d/gcsfuse.list'
            $sh_c 'curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -'
            $sh_c 'apt-get update -y'
            $sh_c 'DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common curl collectd'
            $sh_c 'DEBIAN_FRONTEND=noninteractive apt-get install -y gcsfuse'
            test -n "$SUDO_USER" && $sh_c "usermod -a -G fuse $SUDO_USER" || true
            ;;
    esac
}

do_install

cd /tmp
NOW="$(date +'%Y%m%d-%H%M')"
IP="$(get_metadata_value network-interfaces/0/ip)"
HOSTNAME_F="$(get_metadata_value hostname)"
HOSTNAME_S="${HOSTNAME_F%%.*}"
HOSTSENTRY="$IP       $HOSTNAME_F $HOSTNAME_S  #xcalar_added"
CLUSTER="$(get_metadata_value attributes/cluster)"
if [ -z "$CLUSTER" ]; then
    CLUSTER="${HOSTNAME_S%%-[0-9]*}"
fi
COUNT=$(get_metadata_value attributes/count)

CLUSTERDIR=/mnt/nfs/cluster/$CLUSTER
NFSMOUNT=/mnt/xcalar

$sh_c "cp /etc/hostname /etc/hostname.${NOW}"
$sh_c "echo $HOSTNAME_S > /etc/hostname"
$sh_c "cp /etc/hosts /etc/hosts.${NOW}"
$sh_c 'sed -i -e "/#xcalar_added$/d" /etc/hosts'
$sh_c 'sed -i -e "/'$IP'/d" /etc/hosts'
$sh_c "echo "$HOSTSENTRY" >> /etc/hosts"
$sh_c "hostname $HOSTNAME_S"

$sh_c 'mkdir -p /mnt/nfs'
$sh_c 'sed -i -e "/\/mnt\/nfs/d" /etc/fstab'
$sh_c 'echo "nfs:/srv/share/nfs /mnt/nfs   nfs defaults 0   0" >> /etc/fstab'
$sh_c 'mount -a'
mkdir -p $CLUSTERDIR/members

$sh_c 'mkdir -m 0777 -p /var/opt/xcalar /var/opt/xcalar/stats'

$sh_c "mkdir -m 0777 -p $NFSMOUNT"
$sh_c "sed -i '/$CLUSTER/d' /etc/fstab"
$sh_c "echo 'nfs:/srv/share/nfs/cluster/$CLUSTER   $NFSMOUNT nfs defaults 0   0' >> /etc/fstab"
$sh_c 'mount -a'

#test -f /etc/hosts.orig || $sh_c 'cp /etc/hosts /etc/hosts.orig'
#(cat /etc/hosts.orig ; echo "$IP    $(hostname -f) $(hostname -s)") > /tmp/hosts && $sh_c 'mv /tmp/hosts /etc/hosts'
$sh_c "echo $HOSTSENTRY | tee $CLUSTERDIR/members/$HOSTNAME_F"
#$sh_c "echo '$IP   $(hostname -f) $(hostname -s)' | tee $CLUSTERDIR/members/$(hostname -f)"

# Add xcalar-qa and netstore only for non preview
if ! echo "$CLUSTER" | grep -q '^preview-'; then
    $sh_c 'mkdir -p /netstore/datasets'
    $sh_c 'mkdir -p /xcalar-qa'
    $sh_c 'sed -i -e "/\/netstore\/datasets/d" /etc/fstab'
    $sh_c 'echo "nfs:/srv/datasets /netstore/datasets   nfs defaults 0   0" >> /etc/fstab'
    $sh_c 'sed -i -e "/xcalar-qa/d" /etc/fstab'
    $sh_c 'echo "xcqa /xcalar-qa   gcsfuse defaults,implicit_dirs" >> /etc/fstab'
    $sh_c 'mount -a'
else
    umount /mnt/nfs
    $sh_c 'sed -i -e "/\/mnt\/nfs/d" /etc/fstab'
fi

# XXX Should use puppet manifest
# Set up collectd
$sh_c 'service collectd stop'
writeGraphiteCommon='
LoadPlugin write_graphite
<Plugin write_graphite>
    <Node \"graphite\">
        Host "graphite" # graphite.c.angular-expanse-99923.internal
        Port \"2003\"
        Protocol \"tcp\"
        LogSendErrors false
        Prefix \"collectd.'$CLUSTER'.\"
        Postfix \"\"
        StoreRates true
        AlwaysAppendDS false
        EscapeCharacter \"_\"
    </Node>
</Plugin>
'

if test -e /etc/redhat-release; then
    graphiteConfFile="/etc/collectd.d/collectd.conf"
    writeGraphite='
Hostname'$(hostname -f)'
FQDNLookup false
'"$writeGraphiteCommon"
else
    graphiteConfFile="/etc/collectd/colectd.conf"
    writeGraphite="$writeGraphiteCommon"
    $sh_c "sed -i -e \"s/localhost/$(hostname -f)/\" $graphiteConfFile"
    $sh_c "sed -i -e \"s/FQDNLookup true/FQDNLookup false/\" $graphiteConfFile"
fi

$sh_c "echo \"$writeGraphite\" >> $graphiteConfFile"
$sh_c 'service collectd start'

# Download and run the installer
WORKDIR=/var/tmp/gce-userdata
mkdir -p "$WORKDIR"
mkdir -p $NFSMOUNT/config
safe_curl "$(get_metadata_value attributes/ldapConfig)" >$WORKDIR/ldapConfig.json
if ! test -e /etc/redhat-release; then
    sed -i -e "s@/etc/pki/tls/cert.pem@/etc/ssl/certs/ca-certificates.crt@" $WORKDIR/ldapConfig.json
fi
if [[ $HOSTNAME_S == *1 ]]; then
    cp $WORKDIR/ldapConfig.json $NFSMOUNT/config
fi
safe_curl "$(get_metadata_value attributes/installer)" >$WORKDIR/xcalar-installer
get_metadata_value attributes/config >$WORKDIR/config
$sh_c 'mkdir -p /etc/xcalar'
sed -e 's@^Constants.XcalarRootCompletePath=.*$@Constants.XcalarRootCompletePath='$NFSMOUNT'@g' $WORKDIR/config >$WORKDIR/config-nfs
$sh_c "cp $WORKDIR/config-nfs /etc/xcalar/default.cfg"

set +e
set -x
grep -v '#' /etc/default/xcalar >/etc/default/xcalar.default
rm -f /etc/default/xcalar

$sh_c 'service apache2 stop'
$sh_c 'service httpd stop'

$sh_c "bash -x $WORKDIR/xcalar-installer --noStart --startOnBoot"
cat /etc/default/xcalar.default | tee -a /etc/default/xcalar
$sh_c 'service rsyslog restart'
cd ~xcalar || cd /var/tmp

get_metadata_value attributes/license >/etc/xcalar/temp
get_metadata_value attributes/license | base64 -d | gunzip >/etc/xcalar/XcalarLic.key

if [ "$ELVERSION" == 7 ] || systemctl cat xcalar.service >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl start xcalar.service
else
    /sbin/service xcalar start
fi
