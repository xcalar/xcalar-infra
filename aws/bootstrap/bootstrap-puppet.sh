#!/bin/bash
set +e
safe_curl () {
	curl -4 -L --retry 10 --retry-delay 3 --retry-max-time 60 "$@"
}

echo '172.31.6.119  puppet' | tee -a /etc/hosts
curl -L https://storage.googleapis.com/repo.xcalar.net/scripts/install-aws-deps.sh | bash
export PATH="$PATH:/opt/aws/bin:/opt/puppetlabs/bin"
for retry in 1 2 3; do
  echo >&2 "Puppet try $retry of 3"
  puppet agent -t -v
  rc=$?
  if [ $rc -eq 0 ] || [ $rc -eq 2 ]; then
   echo "Success!!"
   exit 0
  fi
done
exit 1
