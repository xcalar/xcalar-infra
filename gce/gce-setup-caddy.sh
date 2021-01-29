#!/bin/bash

XLRINFRA="$(cd "$(dirname ${BASH_SOURCE[0]})/.." && pwd)"

for host in "$@"; do
    host_short="${host%%.*}"
    gcloud compute instances add-tags ${host_short} --tags http-server-world,https-server-world
    gcloud compute copy-files $XLRINFRA/bin/install-caddy.sh ${host_short}:.
    gcloud compute ssh ${host_short} -- "sudo bash -ex ./install-caddy.sh $host"
done
