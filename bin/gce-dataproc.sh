#!/bin/bash


export CLOUDSDK_COMPUTE_REGION=${CLOUDSDK_COMPUTE_REGION-us-central1}
export CLOUDSDK_COMPUTE_ZONE=${CLOUDSDK_COMPUTE_ZONE-us-central1-f}


usage()
{
    cat << EOF
    Create Dataproc Cluster within GCE.

    Example invocation:
        $myName -c my-cluster-test -m n1-standard-4 -n 3 -w n1-standard-4 -b bucket-name-store-data

        -c <name>       GCE cluster name
        -m <type>       Master instance type (eg n1-standard-8)
        -n <nodes>      Number of woker in cluster
        -w <type>       Worker instance type (eg n1-standard-8)
        -S <size>       Master disk siez(GB)
        -s <size>       Worker disk size(GB)
        -b <bucket>     Bucket to store the data
        -f <fire rule>  Fire Rule Name to set port 10000 open, default name "sparkport"
        -D <disk type>  Master instance disk type, defult pd-standard
        -d <disk type>  Woker instance disk type, default pd-standard
EOF
}

while getopts "c:m:n:w:S:s:b:f:" opt; do
  case $opt in
      c) CLUSTERNAME="$OPTARG";;
      m) MASTER_TYPE="$OPTARG";;
      n) NUM_WORKER="$OPTARG";;
      w) WORKER_TYPE="$OPTARG";;
      S) MASTER_DISK_SIZE="$OPTARG";;
      s) WORKER_DISK_SIZE="$OPTARG";;
      b) BUCKET="$OPTARG";;
      f) FRULE="$OPTARG";;
      *) usage; exit 0;;
  esac
done

if [ -z "$CLUSTERNAME" ] || [ -z "$BUCKET" ]; then
    echo "cluster name or bucket is required"
    exit 1
fi

IMAGE='1.3-deb9'
FRULE="${FRULE:-sparkport}"
MASTER_DISK_TYPE="${MASTER_DISK_TYPE:-pd-standard}"
WORKER_DISK_TYPE="${WORKER_DISK_TYPE:-pd-standard}"
NUM_WORKER="${NUM_WORKER:-2}"
MASTER_TYPE="${MASTER_TYPE:-n1-standard-8}"
WORKER_TYPE="${WORKER_TYPE:-$MASTER_TYPE}"

if [ -z "$MASTER_DISK_SIZE" ]; then
    case "$MASTER_TYPE" in
        n1-highmem-16) MASTER_DISK_SIZE=400;;
        n1-highmem-8) MASTER_DISK_SIZE=200;;
        n1-standard*) MASTER_DISK_SIZE=80;;
        g1-*) MASTER_DISK_SIZE=80;;
        *) MASTER_DISK_SIZE=80;;
    esac
fi

if [ -z "$WOKER_DISK_SIZE" ]; then
    case "$WORKER_TYPE" in
        n1-highmem-16) WORKER_DISK_SIZE=400;;
        n1-highmem-8) WORKER_DISK_SIZE=200;;
        n1-standard*) WORKER_DISK_SIZE=80;;
        g1-*) WORKER_DISK_SIZE=80;;
        *) WORKER_DISK_SIZE=80;;
    esac
fi

getMasterIp() {
    gcloud compute instances describe "${CLUSTERNAME}-m" \
        --format='value[](networkInterfaces.accessConfigs.natIP)' \
        | python -c 'import sys; print(eval(sys.stdin.readline())[0]);'
}

rcmd() {
    args="$@"
    gcloud compute ssh "$CLUSTERNAME-m" --command "$args"
}

setSparkServer(){
    rcmd sudo service hive-server2 stop
    rcmd sudo -u spark /usr/lib/spark/sbin/start-thriftserver.sh
}

cleanup () {
    gcloud dataproc clusters delete -q $CLUSTERNAME || true
    gcloud compute firewall-rules delete -q $FRULE  || true
}

die () {
    cleanup
    exit $1
}

gcloud dataproc clusters create ${CLUSTERNAME} --bucket ${BUCKET} \
    --master-machine-type ${MASTER_TYPE} \
    --master-boot-disk-size ${MASTER_DISK_SIZE} \
    --num-workers ${NUM_WORKER} \
    --worker-machine-type ${WORKER_TYPE} \
    --worker-boot-disk-size ${WORKER_DISK_SIZE} \
    --image-version $IMAGE \
    --scopes 'https://www.googleapis.com/auth/cloud-platform' \
    --tags http-server,https-server

res=${PIPESTATUS[0]}
if [ "$res" -ne 0 ]; then
    die
fi

gcloud compute firewall-rules create ${FRULE} --direction=INGRESS --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:10000 \
    --source-ranges=0.0.0.0/0

res=${PIPESTATUS[0]}
if [ "$res" -ne 0 ]; then
    die
fi

setSparkServer
getMasterIp


