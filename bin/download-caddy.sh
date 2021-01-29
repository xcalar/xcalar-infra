#!/bin/bash
# vim: sw=2:sts=2:ts=2:et:
#
# Downloads the current version of caddy with the set of default plugins
# if none are provided on the cli

set -e

PLUGINS=(\
http.authz
http.awslambda
http.cache
http.cors
http.expires
http.filter
http.forwardproxy
http.git
http.gopkg
http.grpc
http.hugo
http.ipfilter
http.jwt
http.login
http.minify
http.prometheus
http.proxyprotocol
http.realip
http.restic
http.upload
net
tls.dns.googlecloud
tls.dns.route53)

strjoin () { local IFS="$1"; shift; echo "$*"; }

caddy_url () {
  echo "https://caddyserver.com/download/linux/amd64?plugins=$(strjoin , "$@")"
}

main () {
  while getopts "ho:" opt "$@"; do
    case $opt in
      h)
        cat >&2 <<EOF
        usage: $0 [-h] [-o output.tar.gz] -- plugins ..
        -o output.tar.gz     set output file (default: caddy_linux_amd64_custom-\${CADDY_VERSION}.tar.gz
        -- plugins ...       specify plugins (default: ${PLUGINS[*]})
EOF
        exit 1
      ;;
      o) OUTPUT="$OPTARG";;
      --) break;;
      *) echo >&2 "Uknown argument $opt $OPTARG"; exit 1;;
    esac
  done
  shift $((OPTIND-1))

  test $# -gt 0 || set -- "${PLUGINS[@]}"

  TMP="$(mktemp)"
  curl -sSL "$(caddy_url "$@")" > "$TMP"
  CADDY_VERSION="$(tar zxf "$TMP" -O CHANGES.txt | head | grep -E '^[0-9]\.[0-9]+' | head -1 | awk '{print $1}')"

  : "${OUTPUT:=caddy_linux_amd64_custom-${CADDY_VERSION}.tar.gz}"
  mv "$TMP" "$OUTPUT"
}

main "$@"
