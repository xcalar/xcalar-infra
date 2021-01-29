#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

BUILD_PROTOCOL=${BUILD_PROTOCOL:-"1.3.0"}

[ -z "$BUILD_CLUSTER_IMAGE" ] && die 1 "BUILD_CLUSTER_IMAGE is not set"
[ -z "$BUILD_CLUSTER_OS" ] && die 1 "BUILD_CLUSTER_OS is not set"
[ -z "$BUILD_CLUSTER_PROJECT" ] && die 1 "BUILD_CLUSTER_PROJECT is not set"
[ -z "$BUILD_CLUSTER_SIZE" ] && die 1 "BUILD_CLUSTER_SIZE is not set"
[ -z "$BUILD_INSTALLER_DIR" ] && die 1 "BUILD_INSTALLER_DIR is not set"
[ -z "$BUILD_INSTALLER_FILE" ] && die 1 "BUILD_INSTALLER_FILE is not set"
[ -z "$BUILD_INSTALL_DIR" ] && die 1 "BUILD_INSTALL_DIR is not set"
[ -z "$BUILD_LDAP_SERVER" ] && die 1 "BUILD_LDAP_SERVER is not set"
[ -z "$BUILD_LDAP_TYPE" ] && die 1 "BUILD_LDAP_TYPE is not set"
[ -z "$BUILD_LICENSE_FILE" ] && die 1 "BUILD_LICENSE_FILE is not set"
[ -z "$BUILD_NFS_MOUNT_ROOT" ] && die 1 "BUILD_NFS_MOUNT_ROOT is not set"
[ -z "$BUILD_NFS_SERVER" ] && die 1 "BUILD_NFS_SERVER is not set"
[ -z "$BUILD_NFS_SERVER_EXT" ] && die 1 "BUILD_NFS_SERVER_EXT is not set"
[ -z "$BUILD_NFS_TYPE" ] && die 1 "BUILD_NFS_TYPE is not set"
[ -z "$BUILD_PRECONFIG_FILE" ] && die 1 "BUILD_PRECONFIG_FILE is not set"
[ -z "$BUILD_PUBLIC_KEY" ] && die 1 "BUILD_PUBLIC_KEY is not set"
[ -z "$BUILD_SERDES_DIR" ] && die 1 "BUILD_SERDES_DIR is not set"
[ -z "$BUILD_TEST_NAME" ] && die 1 "BUILD_TEST_NAME is not set"
[ -z "$CLOUD_PROVIDER" ] && die 1 "CLOUD_PROVIDER is not set"

BUILD_CERT_FILE=/etc/pki/tls/cert.pem

is_int_ext "BUILD_LDAP_TYPE" "$BUILD_LDAP_TYPE"
is_int_ext "BUILD_NFS_TYPE" "$BUILD_NFS_TYPE"

case "${CLOUD_PROVIDER}" in
    aws)
        BUILD_USERNAME=ec2-user
        TESTINSTALL_HOST_IMAGE=${TESTINSTALL_HOST_IMAGE:-ami-4185e621}
        TESTINSTALL_MACHINE_TYPE=${TESTINSTALL_MACHINE_TYPE:-m5.xlarge}
        TESTHOST_IMAGE=${TESTHOST_IMAGE:-ami-4185e621}
        TESTHOST_MACHINE_TYPE=${TESTHOST_MACHINE_TYPE:-m5.xlarge}
        TESTCLUSTER_IMAGE="${BUILD_CLUSTER_IMAGE}"
        TESTCLUSTER_MACHINE_TYPE=${TESTCLUSTER_MACHINE_TYPE:-m5.xlarge}
        ;;
    gce)
        BUILD_USERNAME=${BUILD_USERNAME:-"$(id -un)"}
        TESTINSTALL_HOST_IMAGE=${TESTINSTALL_HOST_IMAGE:-centos-7-v20170227}
        TESTINSTALL_MACHINE_TYPE=${TESTINSTALL_MACHINE_TYPE:-g1-small}
        TESTHOST_IMAGE=${TESTHOST_IMAGE:-centos-7-v20170227}
        TESTHOST_MACHINE_TYPE=${TESTHOST_MACHINE_TYPE:-n1-standard-2}
        TESTCLUSTER_IMAGE="${BUILD_CLUSTER_IMAGE}"
        TESTCLUSTER_MACHINE_TYPE=${TESTCLUSTER_MACHINE_TYPE:-n1-highmem-4}
        ;;
esac
INACTIVE_SERVICES="${INACTIVE_SERVICES:-sqldf}"

cat <<EOF
{
    "TestName": "$BUILD_TEST_NAME",
    "DockerInstallHostConfig": {
        "OSVersion": "CENTOS7",
        "OSImage": "${TESTINSTALL_HOST_IMAGE}",
        "OSProject": "centos-cloud",
        "DockerSource": "RPM",
        "MachineType": "${TESTINSTALL_MACHINE_TYPE}"
    },
    "TestHostConfig": {
        "OSVersion": "CENTOS7",
        "OSImage": "${TESTHOST_IMAGE}",
        "OSProject": "centos-cloud",
        "MachineType": "${TESTHOST_MACHINE_TYPE}"
    },
    "TestClusterConfig": {
        "ServerCount": $BUILD_CLUSTER_SIZE,
        "OSVersion": "$BUILD_CLUSTER_OS",
        "OSImage": "$BUILD_CLUSTER_IMAGE",
        "OSProject": "$BUILD_CLUSTER_PROJECT",
        "MachineType": "${TESTCLUSTER_MACHINE_TYPE}"
    },
    "InstallerFile": {
        "Name": "$BUILD_INSTALLER_FILE",
        "Source": "$BUILD_INSTALLER_DIR",
        "Protocol": "$BUILD_PROTOCOL",
        "PreConfigFile": "$BUILD_PRECONFIG_FILE",
        "InactiveServices": "$INACTIVE_SERVICES"
    },
    "Build": {
        "InstallerLoc": "INT",
        "IntLdapPassword": "welcome1",
        "IntLdapDomain": "xcalar.com",
        "IntLdapOrg": "Xcalar, Inc.",
        "ExtLdapUri": "ldap://${BUILD_LDAP_SERVER}:389",
        "ExtLdapUserDn": "mail=%username%,ou=People,dc=int,dc=xcalar,dc=com",
        "ExtLdapFilter": "(memberof=cn=xceUsers,ou=Groups,dc=int,dc=xcalar,dc=com)",
        "ExtLdapCertFile": "$BUILD_CERT_FILE",
        "ExtLdapActiveDir": "false",
        "ExtLdapUseTLS": "true",
        "NfsServer": "$BUILD_NFS_SERVER",
        "NfsServerExt": "$BUILD_NFS_SERVER_EXT",
        "NfsMount": "$BUILD_NFS_MOUNT_ROOT",
        "NfsUser": "",
        "NfsGroup": "",
        "InstallDir": "$BUILD_INSTALL_DIR",
        "SerDes": "$BUILD_SERDES_DIR",
        "LdapType": "$BUILD_LDAP_TYPE",
        "NfsType": "$BUILD_NFS_TYPE"
    },
    "BuildCase": {
        "BasicInstall": {
        },
        "BasicInstallExt": {
            "LdapType": "EXT",
            "NfsType": "EXT"
        },
        "BasicInstallPub": {
            "InstallerLoc": "INT"
        },
        "BasicInstallPubExt": {
            "InstallerLoc": "INT",
            "LdapType": "EXT",
            "NfsType": "EXT"
        }
    },
    "InstallUsername": "$BUILD_USERNAME",
    "LicenseFile": "$BUILD_LICENSE_FILE",
    "AccessPublicKey": "$BUILD_PUBLIC_KEY"
}
EOF
