#!/bin/bash

DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"
DIR="$(readlink -f $DIR)"

. $DIR/integration-sh-lib

MY_NAME=$(basename $0)
echo '#'
echo "# $MY_NAME $@"
echo '#'

remote_path="PATH=/usr/sbin:/usr/bin:/sbin:/bin:\$PATH"

usage() {
    say "usage: $0 [-h|--help] [-x] [-o <output file>] -f <test JSON file>"
    say "-x - enable installer file caching"
    say "-o - print cluster config data into a file"
    say "-h|--help - this help message"
}

parse_args() {

    if [ -z "$1" ]; then
        usage
        exit 1
    fi

    while test $# -gt 0; do
        cmd="$1"
        shift
        case $cmd in
            --help|-h)
                usage
                exit 1
                ;;
            -x)
                GUI_INSTALL_CACHE=1
                ;;
            -o)
                OUTPUT_FILE="$1"
                shift
                ;;
            -f)
                TEST_FILE="$1"
                shift

                if [ ! -e "$TEST_FILE" ]; then
                    say "Test config file $TEST_FILE does not exist"
                    exit 1
                fi
                ;;
            *)
                say "Unknown command $cmd"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$TEST_FILE" ]; then
        say "No test file specified"
        exit 1
    fi

    if [ -e "$OUTPUT_FILE" ]; then
        say "Deleting existing output file $OUTPUT_FILE"
        rm -r $OUTPUT_FILE
    fi

    case "${CLOUD_PROVIDER}" in
        gce)
            GCE_NO_INSTALLER=$($XLRINFRADIR/gce/gce-cluster.sh -h 0<&- 2>&1 | grep "no-installer")
            if [ -z "$GCE_NO_INSTALLER" ]; then
                say "$XLRINFRADIR/gce/gce-cluster.sh does not have the --no-installer option"
                say "Please update your xcalar-infra installation"
                exit 1
            fi
            ;;
    esac
}

parse_test_file() {
    task "Parsing test config file"
    t_start="$(date +%s)"

    TEST_NAME=$(jq -r ".TestName" $TEST_FILE)
    if [ -z "${EXISTING_CLUSTER}" ]; then
        TEST_ID=$RANDOM
    else
        TEST_ID="${EXISTING_CLUSTER}"
    fi

    TEST_NAME="${CLOUD_PROVIDER}"installtest-"${TEST_NAME}-${TEST_ID}"
    SERVER_COUNT=$(jq -r ".TestClusterConfig.ServerCount" $TEST_FILE)
    INSTALLER_FILE=$(jq -r ".InstallerFile.Name" $TEST_FILE)
    INSTALLER_SRC=$(jq -r ".InstallerFile.Source" $TEST_FILE)
    eval INSTALLER_SRC=$INSTALLER_SRC
    INSTALLER_SRC=$(readlink -f "$INSTALLER_SRC")
    CLUSTER_INSTANCE_OSVER=$(jq -r ".TestClusterConfig.OSVersion" $TEST_FILE)
    CLUSTER_INSTANCE_TYPE=$(jq -r ".TestClusterConfig.MachineType" $TEST_FILE)
    INSTALLER_OSVER=$(jq -r ".DockerInstallHostConfig.OSVersion" $TEST_FILE)
    INSTALLER_INSTANCE_TYPE=$(jq -r ".DockerInstallHostConfig.MachineType" $TEST_FILE)
    INSTALLER_DOCKSRC=$(jq -r ".DockerInstallHostConfig.DockerSource" $TEST_FILE)
    TESTHOST_OSVER=$(jq -r ".TestHostConfig.OSVersion" $TEST_FILE)
    TESTHOST_INSTANCE_TYPE=$(jq -r ".TestHostConfig.MachineType" $TEST_FILE)
    ACCESS_PUBKEY=$(jq -r ".AccessPublicKey" $TEST_FILE)
    eval ACCESS_PUBKEY=$ACCESS_PUBKEY
    ACCESS_PUBKEY=$(readlink -f "$ACCESS_PUBKEY")
    if [ -n $ACCESS_PUBKEY ]; then
        ACCESS_PRIVKEY=${ACCESS_PUBKEY%".pub"}
    fi
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))
    echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Parsing test file"
}

create_hosts() {
    t_start="$(date +%s)"
    TEST_PREFIX="$TEST_NAME"
    export NOTPREEMPTIBLE=1
    export IMAGE_VERSION=$(jq -r ".TestClusterConfig.OSVersion" $TEST_FILE)
    export IMAGE=$(jq -r ".TestClusterConfig.OSImage" $TEST_FILE)
    export IMAGE_PROJECT=$(jq -r ".TestClusterConfig.OSProject" $TEST_FILE)
    export INSTANCE_TYPE=$CLUSTER_INSTANCE_TYPE

    task "Starting ${CLOUD_PROVIDER} cluster: $TEST_PREFIX"

    if [ -z "${EXISTING_CLUSTER}" ]; then
        cloud_cluster_create "--no-installer" $SERVER_COUNT "$TEST_PREFIX" 0<&- >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
    else
        echo "Using existing ${CLOUD_PROVIDER} cluster"
    fi

    CLUSTER_PID=$!
    wait $CLUSTER_PID
    rc=$?
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} cluster successfully started"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} cluster start failed"
        cat $TMPDIR/std* >&2
        return $rc
    fi

    EXT_CLUSTER_IPS=$(cloud_cluster_get_ips external "${TEST_PREFIX}")
    INT_CLUSTER_IPS=$(cloud_cluster_get_ips internal "${TEST_PREFIX}")
    rm -f "/tmp/${TEST_PREFIX}-config.cfg"

    if [ "$IMAGE_VERSION" = "RHEL6" ] && [ "$CLOUD_PROVIDER" = "aws" ] && \
        [ -z "$EXISTING_CLUSTER" ] ; then
        hosts_array=($EXT_CLUSTER_IPS)
        task "Rebooting ${CLOUD_PROVIDER} cluster $TEST_PREFIX to grow root file systems"
        pssh_cmd sudo growpart /dev/xvda 1 && \
            cloud_cluster_reboot "$TEST_PREFIX" && \
            pssh_cmd sudo resize2fs /dev/xvda1
    fi

    t_start="$(date +%s)"
    TEST_PREFIX="${TEST_NAME}-install"
    export IMAGE=$(jq -r ".DockerInstallHostConfig.OSImage" $TEST_FILE)
    export IMAGE_PROJECT=$(jq -r ".DockerInstallHostConfig.OSProject" $TEST_FILE)
    export INSTANCE_TYPE=$INSTALLER_INSTANCE_TYPE

    task "Starting ${CLOUD_PROVIDER} cluster: $TEST_PREFIX"

    if [ -z "${EXISTING_CLUSTER}" ]; then
        cloud_cluster_create "--no-installer" 1 "$TEST_PREFIX" >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
    else
        echo "Using existing ${CLOUD_PROVIDER} cluster"
    fi

    INSTALLER_PID=$!
    wait $INSTALLER_PID
    rc=$?
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} installer successfully started"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} installer start failed"
        cat $TMPDIR/std* >&2
        return $rc
    fi

    EXT_INSTALL_IP=$(cloud_cluster_get_ips external "${TEST_PREFIX}")
    INT_INSTALL_IP=$(cloud_cluster_get_ips internal "${TEST_PREFIX}")
    rm -f "/tmp/${TEST_PREFIX}-config.cfg"

    if [ "$TESTHOST_OSVER" != "null" ]; then
        t_start="$(date +%s)"
        TEST_PREFIX="${TEST_NAME}-test"
        export IMAGE=$(jq -r ".TestHostConfig.OSImage" $TEST_FILE)
        export IMAGE_PROJECT=$(jq -r ".TestHostConfig.OSProject" $TEST_FILE)
        export INSTANCE_TYPE=$TESTHOST_INSTANCE_TYPE

        task "Starting ${CLOUD_PROVIDER} cluster: $TEST_PREFIX"

        if [ -z "${EXISTING_CLUSTER}" ]; then
            cloud_cluster_create "--no-installer" 1 "$TEST_PREFIX" >${TMPDIR}/stdout 2>${TMPDIR}/stderr &
        else
            echo "Using existing ${CLOUD_PROVIDER} cluster"
        fi

        INSTALLER_PID=$!
        wait $INSTALLER_PID
        rc=$?
        t_end="$(date +%s)"
        dt=$(( $t_end - $t_start ))

        if [ $rc -eq 0 ]; then
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} installer successfully started"
        else
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} installer start failed"
            cat $TMPDIR/std* >&2
            return $rc
        fi

        EXT_TEST_IP=$(cloud_cluster_get_ips external "${TEST_PREFIX}")
        INT_TEST_IP=$(cloud_cluster_get_ips internal "${TEST_PREFIX}")
        rm -f "/tmp/${TEST_PREFIX}-config.cfg"

    fi
}

setup_installer_host() {
    rc=0
    t_start="$(date +%s)"
    case $INSTALLER_OSVER in
        rhel6|RHEL6)
            task "Starting RHEL6 installer configuration"
            ssh_cmd $EXT_INSTALL_IP "cd /tmp; curl -O https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo yum -y localinstall /tmp/epel-release-latest-6.noarch.rpm
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo yum -y update
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo yum -y install docker-io.x86_64
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo service docker start
            rc=$(( $rc + $? ))
            ;;
        centos6|CENTOS6)
            task "Starting EL6 installer configuration"
            ssh_cmd $EXT_INSTALL_IP sudo yum -y install epel-release
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo yum -y update
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo yum -y install docker-io.x86_64
            rc=$(( $rc + $? ))
            ssh_cmd $EXT_INSTALL_IP sudo service docker start
            rc=$(( $rc + $? ))
            ;;
        centos7|CENTOS7|rhel7|RHEL7)
            task "Starting EL7 installer configuration"
            ssh_cmd $EXT_INSTALL_IP sudo yum -y update
            rc=$(( $rc + $? ))
            case $INSTALLER_DOCKSRC in
                RPM)
                    ssh_cmd $EXT_INSTALL_IP sudo yum -y install docker.x86_64
                    rc=$(( $rc + $? ))
                    ;;
                Docker)
                    scp_cmd $TMPDIR/docker.repo "${EXT_INSTALL_IP}:"
                    rc=$(( $rc + $? ))
                    ssh_cmd $EXT_INSTALL_IP sudo cp docker.repo /etc/yum.repos.d/
                    rc=$(( $rc + $? ))
                    ssh_cmd $EXT_INSTALL_IP sudo yum -y install docker-engine
                    rc=$(( $rc + $? ))
                    ;;
            esac
            ssh_cmd $EXT_INSTALL_IP sudo systemctl start docker
            rc=$(( $rc + $? ))
            ;;
    esac
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Installer configuration succeeded"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] Installer configuration failed"
        return $rc
    fi
}

setup_test_host() {
    if [ "$TESTHOST_OSVER" != "null" ]; then
        rc=0
        t_start="$(date +%s)"
        NODE=$(echo $INT_CLUSTER_IPS_OUT | cut -d "," -f1)

        task "Starting test host configuration"
        case "$TESTHOST_OSVER" in
            Ubuntu)
                ssh_cmd $EXT_TEST_IP "sudo apt-get update -y"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo apt-get install -y unzip libgconf2-dev libnss3-dev chromium-browser"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo curl -sO http://chromedriver.storage.googleapis.com/2.24/chromedriver_linux64.zip"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo unzip chromedriver_linux64.zip"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo mv chromedriver /usr/bin"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo apt-get install -y libxss1 libappindicator1 libindicator7"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo apt-get install -y python-pip"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo pip install pyvirtualdisplay selenium"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo apt-get install -y Xvfb"
                rc=$(( $rc + $? ))
                ;;
            centos7|CENTOS7)
                ssh_cmd $EXT_TEST_IP "sudo curl -ssL http://repo.xcalar.net/rpm-deps/google-chrome.repo | sudo tee /etc/yum.repos.d/google-chrome.repo"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "curl -sSO https://dl.google.com/linux/linux_signing_key.pub"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo rpm --import linux_signing_key.pub"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo yum install -y google-chrome-stable"
                rc=$(( $rc + $? ))
                scp_cmd "/netstore/infra/packages/chromedriver-2.34-2.el7.x86_64.rpm" "${EXT_TEST_IP}:"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo yum localinstall -y chromedriver-2.34-2.el7.x86_64.rpm"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo yum install -y python-pip"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo pip install pyvirtualdisplay selenium"
                rc=$(( $rc + $? ))
                ssh_cmd $EXT_TEST_IP "sudo yum install -y Xvfb"
                rc=$(( $rc + $? ))
                ;;
        esac
        scp_cmd "${DIR}/server.py" "${EXT_TEST_IP}:"
        rc=$(( $rc + $? ))
        scp_cmd "${DIR}/test-server.pem" "${EXT_TEST_IP}:/tmp"
        rc=$(( $rc + $? ))
        scp_cmd "${DIR}/test-server-key.pem" "${EXT_TEST_IP}:/tmp"
        rc=$(( $rc + $? ))
        bg_ssh_cmd $EXT_TEST_IP "bash -c 'nohup python ./server.py -t $NODE 2>&1 > /tmp/server.log </dev/null &'"
        rc=$(( $rc + $? ))
        t_end="$(date +%s)"
        dt=$(( $t_end - $t_start ))

        if [ $rc -eq 0 ]; then
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] Test host configuration succeeded"
        else
            echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] Test host configuration failed"
            return $rc
        fi
    fi
}

setup_backup_disk() {
    cloud_create_backup_disk "${TEST_NAME}" "${NODE_NAME_ZERO}"
    return $?
}

setup_cluster_auth() {
    rc=0
    hosts_array=($EXT_CLUSTER_IPS)
    task "Setting up ${CLOUD_PROVIDER} cluster authentication"
    t_start="$(date +%s)"

    case $CLUSTER_INSTANCE_OSVER in
        centos7|CENTOS7|rhel7|RHEL7)
            pssh_cmd sudo yum -y update
            pssh_cmd sudo yum install -y net-tools bind-utils
            ;;
        centos6|CENTOS6|rhel6|RHEL6)
            pssh_cmd sudo yum -y update
            pssh_cmd '! command -v scp >/dev/null 2>&1 && sudo yum install -y openssh-clients'
            ;;
    esac

    case "${CLOUD_PROVIDER}" in
        aws)
            owner="ec2-user"
            ;;
        gce)
            owner=$(id -un)
            ;;
    esac

    for host in ${EXT_CLUSTER_IPS}; do
        scp_cmd "$ACCESS_PUBKEY" "${host}:pubkey.pub"
        rc=$(( $rc + $? ))
        ssh_cmd "${host}" "cat pubkey.pub >> .ssh/authorized_keys"
        rc=$(( $rc + $? ))
        ssh_cmd "${host}" rm -f pubkey.pub
        rc=$(( $rc + $? ))
        ssh_cmd "${host}" sudo mkdir -p /opt/xcalar
        rc=$(( $rc + $? ))
        ssh_cmd "${host}" sudo mkdir -p /serdes
        rc=$(( $rc + $? ))
        ssh_cmd "${host}" "sudo chown ${owner}:${owner} /opt/xcalar /serdes"
        rc=$(( $rc + $? ))

        if [ $rc -ne 0 ]; then
            break
        fi
    done
    t_end="$(date +%s)"
    dt=$(( $t_end - $t_start ))

    if [ $rc -eq 0 ]; then
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [SUCCESS] ${CLOUD_PROVIDER} cluster auth configuration succeeded"
    else
        echo "[0] $(date --utc -d@$dt +'%H:%M:%S') [FAILURE] ${CLOUD_PROVIDER} cluster auth configuration failed"
        return $rc
    fi
}

parse_args "$@"

create_cache_dir || die 1 "Unable to create cache dir"

parse_test_file

if [ -z "$ACCESS_PUBKEY" ] || [ ! -e $ACCESS_PUBKEY ] || [ ! -e $ACCESS_PRIVKEY ]; then
    if [ "$ACCESS_PUBKEY" != "$ACCESS_PRIVKEY" ]; then
        say "Either change the value of AccessPublicKey or try running this command:"
        say "ssh-keygen -b 2048 -t rsa -f $ACCESS_PRIVKEY -q -N \"\""
    else
        say "Check the value of AccessPublicKey in the test config file"
    fi
    exit 1
fi

get_installer_file || die 1 "Unable to get installer file"

create_hosts
rc=$?

if [ -n "$OUTPUT_FILE" ]; then
    echo "TEST_ID=${TEST_ID}" > $OUTPUT_FILE
fi

if [ $rc -ne 0 ]; then
    die 1 "Unable to create ${CLOUD_PROVIDER} cluster hosts"
fi

# fix up the cluster ips for output
EXT_CLUSTER_IPS_OUT=""
for host in ${EXT_CLUSTER_IPS}; do
    if [ -z "$EXT_CLUSTER_IPS_OUT" ]; then
        EXT_CLUSTER_IPS_OUT=$host
        NODE_ZERO=$host
    else
        EXT_CLUSTER_IPS_OUT="$EXT_CLUSTER_IPS_OUT,$host"
    fi
done
case "${CLOUD_PROVIDER}" in
    aws)
        NODE_NAME_ZERO=$NODE_ZERO
        ;;
    gce)
        NODE_NAME_ZERO=$(gcloud compute instances list | grep $NODE_ZERO | awk '{ print $1 }')
        ;;
esac

INT_CLUSTER_IPS_OUT=""
for host in ${INT_CLUSTER_IPS}; do
    if [ -z "$INT_CLUSTER_IPS_OUT" ]; then
        INT_CLUSTER_IPS_OUT=$host
    else
        INT_CLUSTER_IPS_OUT="$INT_CLUSTER_IPS_OUT,$host"
    fi
done

say "${CLOUD_PROVIDER} Cluster External IPs: ${EXT_CLUSTER_IPS_OUT}"
say "${CLOUD_PROVIDER} Cluster Internal IPs: ${INT_CLUSTER_IPS_OUT}"
say "Installer External IP: ${EXT_INSTALL_IP}"
say "Installer Internal IP: ${INT_INSTALL_IP}"
if [ "$TESTHOST_OSVER" != "null" ]; then
    say "Test Host External IP: ${EXT_TEST_IP}"
    say "Test Host Internal IP: ${INT_TEST_IP}"
fi

test -n "$EXISTING_CLUSTER" && echo "Using existing ${CLOUD_PROVIDER} cluster"
set -o pipefail
setup_cluster_auth && \
setup_test_host && \
setup_backup_disk && \
launch_installer && \
installer_ready
rc=$?

if [ $rc -eq 0 ]; then
    say "Please open your browser to https://${EXT_INSTALL_IP}:8543"
    say "Cluster names are ${TEST_NAME} and ${TEST_NAME}-install"
    say "You can delete this setup with the following command:"
    say "delete-gui-installer-test.sh -f $TEST_FILE -n $TEST_ID"

    if [ -n "$OUTPUT_FILE" ]; then
        echo "EXT_CLUSTER_IPS=${EXT_CLUSTER_IPS_OUT}" >> $OUTPUT_FILE
        echo "INT_CLUSTER_IPS=${INT_CLUSTER_IPS_OUT}" >> $OUTPUT_FILE
        echo "EXT_INSTALL_IP=${EXT_INSTALL_IP}" >> $OUTPUT_FILE
        echo "INT_INSTALL_IP=${INT_INSTALL_IP}" >> $OUTPUT_FILE
        if [ "$TESTHOST_OSVER" != "null" ]; then
            echo "EXT_TEST_IP=${EXT_TEST_IP}" >> $OUTPUT_FILE
            echo "INT_TEST_IP=${INT_TEST_IP}" >> $OUTPUT_FILE
        fi
        echo "NODE_NAME_ZERO=${NODE_NAME_ZERO}" >> $OUTPUT_FILE
    fi
else
    say "Failure during xcalar installation"
    say "delete-gui-installer-test.sh -f $TEST_FILE -n $TEST_ID"
fi

exit $rc
