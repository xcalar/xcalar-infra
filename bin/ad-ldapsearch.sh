#!/bin/bash
#
# ad-ldapsearch.sh queries DNS for the AD DC and constructs the
# proper string for an LDAP query such as:
#
#   ldapsearch -h aws-2584d1dcf4.aws.xcalar.com -p 389 -D Administrator@AWS.XCALAR.COM -W -b CN=Users,DC=aws,DC=xcalar,DC=com -s sub '(cn=*)' cn mail sn
#
#
# Usage:
#   ad-ldapsearch.sh [optional: domain.name]
#
# If domain isn't provided, `dnsdomainname` is used to query the DNS name
# The Domain Controller host and port is queried using DNS SRV records
# DOMAIN_USER env var is used to override the default `Administrator`
# BINDDN env var is used to override the default DN to query or the default `CN=Users` is used
#

DOMAIN="${1:-$(dnsdomainname)}"
DOMAIN_USER="${DOMAIN_USER:-Administrator}"
BINDDN="${BINDN:-CN=Users}"
DOMAIN_ARRAY=("${DOMAIN//\./ }")
DOMAIN_UPCASE="$(echo $DOMAIN | tr a-z A-Z)"
DC=()
for dc in "${DOMAIN_ARRAY[@]}"; do
  DC+=("DC=$dc")
done

strjoin () {
    local IFS="$1"
    shift
    echo "$*"
}

lookup_ldapserver () {
    local srv= host= port=
    if srv="$(host -t SRV _ldap._tcp.$1)"; then
        host="$(echo $srv | awk '{print $(NF)}' | sed -e 's/\.$//g')"
        port="$(echo $srv | awk '{print $(NF-1)}')"
        echo $host $port
        return 0
    fi
    return 1
}

HOST_PORT=($(lookup_ldapserver $DOMAIN))

ldapsearch -h "${HOST_PORT[0]}" -p "${HOST_PORT[1]}" -D "${DOMAIN_USER}@${DOMAIN_UPCASE}" -W  -b "$(strjoin , "${BINDDN}" "${DC[@]}")"  -s sub "(cn=*)" cn mail sn
