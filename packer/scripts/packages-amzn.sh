#!/bin/bash

set -ex

export PS4='# $(date +%FT%TZ) ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]}() - [${SHLVL},${BASH_SUBSHELL},$?] '

install_aws_deps() {
    rpm -q awscli && yum remove awscli -y || true
    (
    set -e
    TMPDIR=$(mktemp -d /tmp/awscli-XXXXXX)
    cd $TMPDIR
    curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    if ! command -v unzip >/dev/null; then
        sudo yum install -y unzip
    fi
    unzip awscliv2.zip
    ver=$(aws/dist/aws --version | cut -d' ' -f1 | cut -d'/' -f2)
    bundle=awscliv2-bundle-${ver}.tar.gz
    tar czf $bundle aws
    PREFIX=/opt/awscliv2
    ITERATION=${ITERATION:-1}

    sudo rm -rf $PREFIX
    sudo mkdir -p $PREFIX
    sudo -H aws/install -i $PREFIX -b /usr/bin
    sudo ln -sfn ${PREFIX}/v2/current/bin/aws_completer /usr/bin/
    echo 'complete -C /usr/bin/aws_completer aws' | sudo tee /usr/share/bash-completion/completions/aws >/dev/null
    cd - >/dev/null

    rm -rf $TMPDIR
    )
}

install_ssm_agent() {
    yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm || true
    if [ $(osid -i) = "systemd" ]; then
        systemctl daemon-reload
        systemctl enable amazon-ssm-agent.service || true
    else
        status amazon-ssm-agent || true
    fi
    yum locallinstall -y https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm


}

install_osid() {
    curl -fsSL http://repo.xcalar.net/scripts/osid-20191219 -o /usr/bin/osid
    chmod +x /usr/bin/osid
    OSID=${OSID:-$(osid)}
}

fix_cloud_init() {
    sed -i '/package-update-upgrade-install/d' /etc/cloud/cloud.cfg.d/* /etc/cloud/cloud.cfg || true
}

fix_uids() {
    # Amzn1 has UID_MIN and GID_MIN 500. Unbelievable
    sed -r -i 's/^([UG]ID_MIN).*$/\1    1000/' /etc/login.defs
}

install_gdb8() {
    yum install -y optgdb8 --enablerepo='xcalar*'
    for prog in gdb gcore gdbserver; do
        ln -sfn /opt/gdb8/bin/${prog} /usr/local/bin/${prog}
        ln -sfn /opt/gdb8/bin/${prog} /usr/local/bin/${prog}8
    done
}


install_node_exporter() {
    cat > /etc/systemd/system/node_exporter.service<<'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Restart=on-failure
RestartSec=1

Environment="EXCLUDES=--no-collector.hwmon --no-collector.zfs --no-collector.bonding --no-collector.bcache --no-collector.arp --no-collector.edac --no-collector.infiniband --no-collector.ipvs --no-collector.mdadm --no-collector.nfs --no-collector.nfsd --no-collector.wifi --no-collector.conntrack --no-collector.timex"
Environment="OPTIONS=--collector.textfile.directory /var/lib/node_exporter/textfile_collector"
EnvironmentFile=-/etc/sysconfig/node_exporter
ExecStart=/usr/sbin/node_exporter $OPTIONS $EXCLUDES

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /var/lib/node_exporter/textfile_collector
    systemctl daemon-reload
    systemctl enable node_exporter
}

fix_networking() {
    (
        cat > /etc/sysconfig/network <<- EOF
	NETWORKING=yes
	NOZEROCONF=yes
	EOF
        cd /etc/sysconfig/network-scripts
        #sed 's/eth0/eth1/; s/^ONBOOT=.*/ONBOOT=no/' ifcfg-eth0 > ifcfg-eth1
        cat > ifcfg-eth0 <<- EOF
	DEVICE=eth0
	BOOTPROTO=dhcp
	ONBOOT=yes
	TYPE=Ethernet
	USERCTL=yes
	PEERDNS=no
	DHCPV6C=no
	IPV6INIT=no
	PERSISTENT_DHCLIENT=yes
	RES_OPTIONS="timeout:2 attempts:5"
	DHCP_ARP_CHECK=no
	NM_CONTROLLED=no
	EOF

    )
}

install_lego() {
    curl -L https://github.com/go-acme/lego/releases/download/v3.3.0/lego_v3.3.0_linux_amd64.tar.gz | tar zxvf - -C /usr/local/bin
    setcap cap_net_bind_service=+ep /usr/local/bin/lego
}

install_sysdig() {
    curl -s https://s3.amazonaws.com/download.draios.com/stable/install-sysdig | bash
}

main() {
    install_osid
    install_ssm_agent

    echo 'exclude=kernel-debug* *.i?86 *.i686' >> /etc/yum.conf

    yum update -y || true
    yum upgrade -y || true
    yum install -y "https://storage.googleapis.com/repo.xcalar.net/xcalar-release-${OSID}.rpm" || true
    yum clean all --enablerepo='*'
    yum erase -y 'ntp*' || true
    yum install -y --disablerepo='xcalar*' --enablerepo='epel' \
        chrony aws-cfn-bootstrap amazon-efs-utils ec2-net-utils ec2-utils \
        deltarpm curl wget tar gzip htop fuse jq nfs-utils iftop iperf3 sysstat python2-pip \
        lvm2 util-linux bash-completion nvme-cli nvmetcli libcgroup at python-devel \
        libnfs-utils stunnel pigz bash-completion-extras freetds

    sed -i -r 's/stunnel_check_cert_hostname.*$/stunnel_check_cert_hostname = false/' /etc/amazon/efs/efs-utils.conf

    yum install -y --enablerepo='xcalar-deps-common' --enablerepo='epel' \
        ec2tools ephemeral-disk tmux ccache restic lifecycled consul consul-template node_exporter \
        xcalar-node10 opthaproxy2 su-exec tini nomad vault

    yum remove -y python26 python-pip || true

    sed -r -i 's/^#?LV_SWAP_SIZE=.*$/LV_SWAP_SIZE=MEMSIZE2X/; s/^#?LV_DATA_EXTENTS=.*$/LV_DATA_EXTENTS=100%FREE/; s/^#?ENABLE_SWAP=.*/ENABLE_SWAP=1/' /etc/sysconfig/ephemeral-disk
    ephemeral-disk || true

    yum groupinstall -y 'Development tools'

    lsblk
    blkid

    echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/aws/bin:/opt/mssql-tools/bin' > /etc/profile.d/path.sh
    echo -e 'CHECKPOINT_DISABLE=1\nexport CHECKPOINT_DISABLE' | tee /etc/profile.d/checkpoint.sh
    . /etc/profile.d/path.sh

    case "$OSID" in
        amzn1)
            service chronyd start
            service atd start
            echo manual | tee /etc/init/consul.override
            echo manual | tee /etc/init/lifecycled.override

            mkdir -p /run
            echo 'tmpfs  /run   tmpfs   defaults    0   0' >> /etc/fstab

            chkconfig chronyd on
            chkconfig atd on
            fix_uids
            hash -r
            pip-2.7 --no-cache-dir install -U ansible
            install_gdb8
            ;;
        amzn2)
            systemctl enable --now chronyd
            systemctl enable --now atd
            systemctl disable update-motd.service || true
            systemctl mask update-motd.service || true
            #chkconfig network off || true
            #systemctl mask network.service || true
            install_node_exporter
            systemctl enable node_exporter
            amazon-linux-extras install -y ansible2=latest kernel-ng vim=latest BCC=latest
            yum install -y libcgroup-tools gdb || true
            systemctl set-default multi-user.target
            #yum install -y NetworkManager
            #systemctl enable --now NetworkManager.service
            ;;
    esac

    install_aws_deps
    install_sysdig
    fix_cloud_init

    mkdir -p /etc/ansible
    curl -fsSL https://raw.githubusercontent.com/ansible/ansible/devel/examples/ansible.cfg \
        | sed -r 's/^#?([a-z]+)_warnings.*$/\1_warnings = False/; s/^#?host_key_checking.*$/host_key_checking = False/; s/^#?retry_files_enabled.*$/retry_files_enabled = False/; s/^#?forks.*/forks = 50/' > /etc/ansible/ansible.cfg

    for svc in xcalar puppet collectd consul nomad vault lifecycled update-motd; do
        if [ "$OSID" = amzn1 ]; then
            if test -e /etc/init/${svc}.conf; then
                echo manual > /etc/init/${svc}.override
            else
                chkconfig ${svc} off || true
            fi
        else
            systemctl disable ${svc} || true
        fi
    done
    return 0
}

main "$@"
exit
