#!/bin/bash
set -a
if test -r /var/lib/cloud/instance/ec2.env; then
    source /var/lib/cloud/instance/ec2.env
fi
set +a
