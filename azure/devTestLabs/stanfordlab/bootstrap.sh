XCE_CONFIG=${XCE_CONFIG:-/etc/xcalar/default.cfg}
XCE_HOME=${XCE_HOME:-/var/opt/xcalar}
XLRDIR=${XLRDIR:-/opt/xcalar}
XCE_LICENSEDIR=${XCE_LICENSEDIR:-/etc/xcalar}
ADMIN_USERNAME=${ADMIN_USERNAME:-"xcuser"}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-"StanfordLab"}
ADMIN_EMAIL=${ADMIN_EMAIL:-"xcuser@xcalar.com"}
XCALAR_ADVENTURE_DATASET=${XCALAR_ADVENTURE_DATASET:-"http://pub.xcalar.net/datasets/xcalarAdventure.tar.gz"}
XCE_CONFDIR="${XCE_CONFDIR:-/etc/xcalar}"
LICENSE="AEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJAAAJAAAAACAVZHBAJXAXN7SB5D3Y45B7BJSHE62ST8S7N7QWHYP9XQE6AP67552FAS3Y8FXPAE6CXVXGWMDY4YTST2AABWAQ========"
CADDYURL=http://repo.xcalar.net/deps/caddy_linux_amd64_custom-0.10.10.tar.gz
#License key version is: Version 1.0.2
#Product family is: XcalarX
#Product is: Xce
#Product version is: 1.2.2.0
#Product platform is: Linux x86-64
#License expiration is: 10/19/2017
#Node count is: 1
#User count is: 16

safe_curl () {
    curl -4 --location --retry 20 --retry-delay 3 --retry-max-time 60 "$@"
}

postConfig() {
    cp "$XCE_CONFIG" "${XCE_CONFIG}.bak"

    # Turn on support bundles
    echo "Constants.SendSupportBundle=true" | tee -a "$XCE_CONFIG"

    # Add in Azure Blob Storage SAS tokens
    echo "AzBlob.stanfordstudentsdatasets.sasToken=?sv=2017-04-17&ss=b&srt=sco&sp=rwlac&se=2017-10-14T22:55:26Z&st=2017-10-12T14:55:26Z&spr=https&sig=7KpOaXGXX3sID3b1bhPrlIF7m0ALQsuPW9A4PkQ5rm0%3D" | tee -a "$XCE_CONFIG"
    echo "AzBlob.xcalardatawarehouse.sasToken=?sv=2017-04-17&ss=b&srt=sco&sp=rl&se=2017-10-14T23:55:11Z&st=2017-10-12T15:55:11Z&spr=https&sig=%2BKMdhtUbBKrDicTGVAAPzkCXk6azD3DgHAoGbhdN7MQ%3D" | tee -a "$XCE_CONFIG"

    # Burn the trial license
    LICENSE_FILE="$XCE_LICENSEDIR/XcalarLic.key"
    cp "$LICENSE_FILE" "${LICENSE_FILE}.bak"
    echo "$LICENSE" | tee "$LICENSE_FILE"

    mkdir -p "$XCE_HOME/config"
    chown -R xcalar:xcalar "$XCE_HOME/config"

    # Let's retrieve the xcalar adventure datasets now
    if [ ! -d "/netstore" ]; then
        mkdir -p /netstore/datasets/adventure
        safe_curl -sSL "$XCALAR_ADVENTURE_DATASET" > xcalarAdventure.tar.gz
        tar -zxvf xcalarAdventure.tar.gz
        mv XcalarTraining /netstore/datasets/ || true
        mv dataPrep /netstore/datasets/adventure/ || true
        chown -R xcalar:xcalar /netstore
    fi
    # Download puppet
    curl http://repo.xcalar.net/scripts/install-puppet-agent.sh -o /tmp/install-puppet.sh || true
    bash -x /tmp/install-puppet.sh || true

    # Download caddy
    curl -L ${CADDYURL} | tar zxvf - -C ${XLRDIR}/bin caddy
    setcap cap_net_bind_service=+ep ${XLRDIR}/bin/caddy

    # download certs
    curl -L https://xccerts.s3.amazonaws.com/certs/xcalar.io/xcalar-stanfordlab-100.xcalar.io.key -o ${XCE_CONFDIR}/cert.key
    curl -L https://xccerts.s3.amazonaws.com/certs/xcalar.io/xcalar-stanfordlab-100.xcalar.io.pem -o ${XCE_CONFDIR}/cert.pem
    # fix Apache
    sed -i -e 's|^SSLCertificateKeyFile.*$|SSLCertificateKeyFile /etc/xcalar/cert.key|g' /etc/httpd/conf.d/XI-ssl.conf
    sed -i -e 's|^SSLCertificateFile.*$|SSLCertificateFile /etc/xcalar/cert.pem|g' /etc/httpd/conf.d/XI-ssl.conf
    sed -i -e 's|^#SSLCertificateChainFile.*$|SSLCertificateChainFile /etc/xcalar/cert.pem|g' /etc/httpd/conf.d/XI-ssl.conf
    # fix Jupyter
    echo "c.NotebookApp.keyfile = u'/etc/xcalar/cert.key'" >> $XCE_HOME/.jupyter/jupyter_notebook_config.py
    echo "c.NotebookApp.certfile = u'/etc/xcalar/cert.pem'" >> $XCE_HOME/.jupyter/jupyter_notebook_config.py

    # fix Caddyfile
    cp -n ${XCE_CONFDIR}/Caddyfile ${XCE_CONFDIR}/Caddyfile.orig
    (
    echo ":443 {"
    tail -n+2 ${XCE_CONFDIR}/Caddyfile.orig
    echo ":80 {"
    echo "  redir https://{host}{uri}"
    echo "}"
    ) | sed -e "s|tls.*$|tls ${XCE_CONFDIR}/cert.pem ${XCE_CONFDIR}/cert.key|g" -e "s|root.*$|root /var/www/xcalar-gui|g" | tee ${XCE_CONFDIR}/Caddyfile
    chown -R xcalar:xcalar ${XCE_CONFDIR}
    groupadd -r -g 999 docker
    groupadd -r sudo
    echo '%xcuser  ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/xcuser
    echo '%sudo ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sudo
    sed -i -r 's|^#?Port 22.*|Port 22022|g' /etc/ssh/sshd_config

    service xcalar stop-supervisor || true
    service xcalar stop || true
    systemctl stop httpd || true
    systemctl disable httpd || true
    touch ${XCE_CONFDIR}/Caddyfile.run
    service xcalar start
    chown xcalar:xcalar ${XCE_CONFDIR}/Caddyfile.run
    chkconfig xcalar on
    chown xcalar:apache /etc/xcalar/cert.*
    chmod 0640 /etc/xcalar/cert.*
    # AzureCLI (ref: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[azure-cli]\nname=Azure CLI\nbaseurl=https://packages.microsoft.com/yumrepos/azure-cli\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo
    yum makecache fast
    # Some handy tools to have around
    yum install -y htop vim-enhanced iperf3 yum-utils samba-client samba-common cifs-utils \
                   nfs-utils parted gdisk curl \
                   jq python-pip awscli azure-cli \
                   htop iftop iperf3 vim-enhanced tmux
    #yum install -y http://repo.xcalar.net/deps/jdk-8u144-linux-x64.rpm
    #groupadd -g 1000 xcdev
    #useradd -m -s /bin/bash -u 1000 -g 1000 -G docker,sudo xcdev
    echo "Creating default admin user $ADMIN_USERNAME ($ADMIN_EMAIL)"
    # Add default admin user
    jsonData="{ \"defaultAdminEnabled\": true, \"username\": \"$ADMIN_USERNAME\", \"email\": \"$ADMIN_EMAIL\", \"password\": \"$ADMIN_PASSWORD\" }"
    # Don't fail the deploy if this curl doesn't work
    safe_curl -H "Content-Type: application/json" -X POST -d "$jsonData" "http://127.0.0.1:12124/login/defaultAdmin/set" || true
}

postConfig
