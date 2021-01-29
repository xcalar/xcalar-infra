#!/bin/bash
set -x
NUM_INSTANCES=4

safe_curl () {
	curl -4 --fail --location --retry 10 --retry-delay 3 --retry-max-time 60 "$@"
}

INSTANCE_TYPE="$(safe_curl http://169.254.169.254/2016-09-02/meta-data/instance-type)"
LAUNCH_INDEX=$(safe_curl http://169.254.169.254/2016-09-02/meta-data/ami-launch-index)
ZONE="$(safe_curl http://169.254.169.254/2016-09-02/meta-data/placement/availability-zone)"

export AWS_DEFAULT_REGION="${ZONE:0:-1}"

curl -f -L https://storage.googleapis.com/repo.xcalar.net/deps/discover-20180320.tar.gz | tar zxf - -C /usr/local/bin/

IPS=()
while [ "${#IPS[@]}" -lt $NUM_INSTANCES ]; do
   sleep 5
   IPS=($(discover -q addrs provider=aws tag_key=Name tag_value=MyCluster addr_type=priv_v4 2>/dev/null)) # region=$AWS_DEFAULT_REGION
done

/opt/xcalar/scripts/genConfig.sh /etc/xcalar/template.cfg - ${IPS[*]} > /etc/xcalar/default.cfg

service xcalar start
