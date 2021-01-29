#!/bin/bash

set -e

FRULE='sparkport'

usage()
{
    cat << EOF
    Delete Dataproc Cluster within GCE.
        -c <name>       GCE cluster name
        -f <fire rule>  Fire Rule Name to set port 10000 open, dafault name "sparkport"
EOF
}

while getopts "c:f:" opt; do
  case $opt in
      c) CLUSTERNAME="$OPTARG";;
      f) FRULE="$OPTARG";;
      *) usage; exit 0;;
  esac
done

echo "Delete cluster $CLUSTERNAME"
gcloud dataproc clusters delete -q $CLUSTERNAME

echo "Delete firewal rule $FRULE"
gcloud compute firewall-rules delete -q $FRULE
