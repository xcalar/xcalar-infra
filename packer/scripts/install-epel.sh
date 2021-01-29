#!/bin/bash
#
# Script to setup the IUS public repository on your EL server.
# Tested on CentOS/RHEL 6/7.
#
# Adapted from https://setup.ius.io

supported_version_check(){
    case ${RELEASE} in
        6*) echo "EL 6 is supported" ;;
        7*) echo "EL 7 is supported" ;;
        201*) echo "AMZN 1 is supported" ;;
        2) echo "AMZN 2 is supported" ;;
        *)
            echo "Unsupported OS version ${RELEASE}"
            exit 1
            ;;
    esac
}

centos_install_epel(){
    # CentOS has epel release in the extras repo
    if ! yum -y -q install epel-release; then \
        case "${RELEASE}" in
            201*) ELVERSION=6;;
            2*) ELVERSION=7;;
            6*) ELVERSION=6;;
            7*) ELVERSION=7;;
        esac
        yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${ELVERSION}.noarch.rpm
    fi
    import_epel_key
}

amazon_install_epel() {
    case ${RELEASE} in
        201*) yum -y -q install epel-release || yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm || yum localinstall -y -q http://repo.xcalar.net/deps/epel-release-6.noarch.rpm;;
        2) amazon-linux-extras install -y epel;;
    esac
}

rhel_install_epel(){
    # NOTE: Use our repo as a backup because we've seen fedoraproject.org be down
    case ${RELEASE} in
        6*) yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm || yum localinstall -y -q http://repo.xcalar.net/deps/epel-release-6-8.noarch.rpm;;
        7*) yum -y -q install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || yum localinstall -y -q http://repo.xcalar.net/deps/epel-release-7-9.noarch.rpm;;
    esac
    import_epel_key
}

import_epel_key(){
	:
#    case ${RELEASE} in
#        6*) rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6;;
#        7*) rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7;;
#    esac
}

centos_install_ius(){
    case ${RELEASE} in
        6*) yum -y -q install https://centos6.iuscommunity.org/ius-release.rpm; import_ius_key;;
        7*) yum -y -q install https://centos7.iuscommunity.org/ius-release.rpm; import_ius_key;;
    esac
}

rhel_install_ius(){
    case ${RELEASE} in
        6*) yum -y -q install https://rhel6.iuscommunity.org/ius-release.rpm;;
        7*) yum -y -q install https://rhel7.iuscommunity.org/ius-release.rpm;;
    esac
    import_ius_key
}

import_ius_key(){
    true #rpm --import /etc/pki/rpm-gpg/IUS-COMMUNITY-GPG-KEY
}

install_epel() {
    if test -e /etc/system-release; then
        RELEASE_RPM=$(rpm -qf /etc/system-release)
        RELEASE=$(rpm -q ${RELEASE_RPM} --qf '%{VERSION}')
        case ${RELEASE_RPM} in
            centos*)
                echo "detected CentOS ${RELEASE}"
                supported_version_check
                centos_install_epel
                centos_install_ius
                ;;
            oraclelinux*|redhat*)
                echo "detected RHEL ${RELEASE}"
                supported_version_check
                rhel_install_epel
                rhel_install_ius
                ;;
            system-release*)
                echo "detected AMZN ${RELEASE}"
                supported_version_check
                amazon_install_epel
                ;;
            *)
                echo "unknown EL clone"
                exit 1
                ;;
        esac
        # test -e /etc/yum.repos.d/ius.repo && sed -i -E -e 's/enabled=.*$/enabled=1\nexclude=httpd24u\*,mariadb\*,mysql\*/' /etc/yum.repos.d/ius.repo || true
    else
        echo "not an EL distro"
        exit 0
    fi
}

install_epel
