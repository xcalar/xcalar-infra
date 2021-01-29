#!/bin/bash
#
# Get LetsEncrypt SSL certs
#
# Usage:
#    letsencrypt.sh host1.domain.com host2.domain.com ...
#
# You must have your git config user.email set correctly
#
# The way this script works is that you register a wildcard DNS
# name for your domain (say, *.mydomain.com) to point to one host.
# You then run this script on that node. When LE goes to verify
# your hostnames, it'll succeed because the wildcard record points
# to the certbot instance running in this script.
#
# You can use this to generate a cert with up to 100 SANs (subject
# alternative names) in it, giving you close to what a wildcard
# cert would provide. We do this because LE rate limits requests to
# 20/week/domain. Using this script you can get one cert with 100
# valid names and only renew it once every 90 days.
#

if test $# -eq 0; then
    echo >&2 "Usage: $0 host1 host2 ..."
    exit 1
fi

if ! test -d certbot; then
    git clone https://github.com/certbot/certbot
fi

HOSTS=()
for host in "$@"; do
    HOST+=(-d $host)
done

# For example:
# certbot/certbot-auto certonly --standalone email ambakshi@gmail.com \
#                                -d host1.mydomain.com \
#                                -d host2.mydomain.com \
#                                -d host3.mydomain.com

certbot/certbot-auto certonly --standalone --email $(git config user.email) "${HOSTS[@]}"

if ! test -e /etc/letsencrypt; then
    sudo tar czf - etc/letsencrypt -C / > letsencrypt.tar.gz
else
    tar czf - etc/letsencrypt -C / > letsencrypt.tar.gz
fi
