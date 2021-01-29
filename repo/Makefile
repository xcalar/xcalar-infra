.PHONY: all help download upload sync upload-el6-deps release-all upload-release

TMP := $(shell mktemp -u -d --tmpdir repoXXXXXX)
ITERATION ?= 5

all: help


help:
	@echo 'sync      - download then upload files'
	@echo 'download  - download repo files'
	@echo 'upload    - upload repo files (WARNING: files not in source are deleted!)'
	@echo 'release-all   - generate and upload new release packages'


download:
	mkdir -p ./apt ./patches ./rpm ./rpm-deps
	gsutil -m rsync -c -R gs://repo.xcalar.net/apt/ ./apt/
	gsutil -m rsync -c -R gs://repo.xcalar.net/patches/ ./patches/
	gsutil -m rsync -c -R gs://repo.xcalar.net/rpm/ ./rpm/
	gsutil -m rsync -c -R gs://repo.xcalar.net/rpm-deps/ ./rpm-deps/


upload-el6-deps:
	gsutil -m mv gs://repo.xcalar.net/rpm-deps/el6 gs://repo.xcalar.net/rpm-deps/backup/${ITERATION}/
	gsutil -m mv gs://repo.xcalar.net/rpm-deps/el6Server gs://repo.xcalar.net/rpm-deps/backup/${ITERATION}/
	gsutil -m cp -r ./rpm-deps/el6/ gs://repo.xcalar.net/rpm-deps/el6/
	gsutil -m cp -r ./rpm-deps/el6/ gs://repo.xcalar.net/rpm-deps/el6Server/

upload:
	gsutil -m rsync -c -R ./apt/ gs://repo.xcalar.net/apt/
	gsutil -m rsync -c -R ./patches/ gs://repo.xcalar.net/patches/
	gsutil -m rsync -c -R ./rpm/ gs://repo.xcalar.net/rpm/
	gsutil -m rsync -c -R ./rpm-deps/ gs://repo.xcalar.net/rpm-deps/

sync: download upload

xcalar-release-1.0-$(ITERATION).x86_64.rpm: pubkey.gpg rpm/xcalar.repo rpm-deps/xcalar-deps.repo
	mkdir -p $(TMP)/etc/pki/rpm-gpg $(TMP)/etc/yum.repos.d
	cp $< $(TMP)/etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar
	cp $(filter-out $<,$^) $(TMP)/etc/yum.repos.d/
	printf '#!/bin/sh\nrpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar || true\n' > $(TMP)/after.sh && chmod +x $(TMP)/after.sh
	fpm -s dir -t rpm -n xcalar-release \
        --url http://xcalar.com --description 'Xcalar Yum Repositories' \
        --maintainer info@xcalar.com --vendor 'Xcalar, Inc.' --license Proprietary \
        -v 1.0 --after-install $(TMP)/after.sh --iteration $(ITERATION) -C $(TMP) etc
	rm -rf $(TMP)

ALL = xcalar-release-bionic.deb xcalar-release-trusty.deb xcalar-release-el.rpm xcalar-rhel-mirror.rpm
release-all: $(ALL)

xcalar-release-trusty.deb: xcalar-release/after-install.sh xcalar-release/usr/share/xcalar/gpg/pubkey.gpg xcalar-release/etc/apt/sources.list.d/xcalar.list
	/bin/echo -ne 'deb [arch=amd64] http://repo.xcalar.net/apt/ubuntu trusty main\n' > xcalar-release/etc/apt/sources.list.d/xcalar.list
	fpm -s dir -t deb -f --name xcalar-release --package $@ --version 1.0 --iteration $(ITERATION) --deb-no-default-config-files --vendor 'Xcalar, Inc.' --description 'Xcalar APT Repo' --after-install xcalar-release/after-install.sh -C xcalar-release etc usr

xcalar-release-bionic.deb: xcalar-release/after-install.sh xcalar-release/usr/share/xcalar/gpg/pubkey.gpg xcalar-release/etc/apt/sources.list.d/xcalar.list
	/bin/echo -ne 'deb [trusted=yes arch=amd64] http://repo.xcalar.net/apt/ubuntu bionic main\n' > xcalar-release/etc/apt/sources.list.d/xcalar.list
	fpm -s dir -t deb -f --name xcalar-release --package $@ --version 1.0 --iteration $(ITERATION) --deb-no-default-config-files --vendor 'Xcalar, Inc.' --description 'Xcalar APT Repo' --after-install xcalar-release/after-install.sh -C xcalar-release etc usr

xcalar-release-el.rpm: xcalar-release-el/etc/yum.repos.d/xcalar.repo xcalar-release-el/etc/yum.repos.d/xcalar-deps.repo xcalar-release-el/etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar
	fpm -s dir -t rpm -f --name xcalar-release --package $@ --version 1.0 --iteration $(ITERATION) --vendor 'Xcalar, Inc.' --description 'Xcalar YUM Repo' -C xcalar-release-el etc

%.rpm: %/etc/yum.repos.d/xcalar.repo %/etc/yum.repos.d/xcalar-deps.repo %/etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar
	fpm -s dir -t rpm -f --name xcalar-release --package $@ --version 1.0 --iteration $(ITERATION) --vendor 'Xcalar, Inc.' --description 'Xcalar YUM Repo' -C `basename $@ .rpm` .

#xcalar-release-amzn2.rpm: xcalar-release-amzn2/etc/yum.repos.d/xcalar.repo xcalar-release-amzn2/etc/yum.repos.d/xcalar-deps.repo xcalar-release-amzn2/etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar
#	fpm -s dir -t rpm -f --name xcalar-release --package $@ --version 1.0 --iteration $(ITERATION) --vendor 'Xcalar, Inc.' --description 'Xcalar YUM Repo' -C xcalar-release-amzn2 etc

xcalar-rhel-mirror.rpm: xcalar-rhel-mirror/etc/yum.repos.d/xcalar-rhel-mirror.repo xcalar-rhel-mirror/etc/pki/rpm-gpg/RPM-GPG-KEY-Xcalar-RHEL-Mirror
	fpm -s dir -t rpm -f --name xcalar-rhel-mirror --package $@ --version 1.0 --iteration $(ITERATION) --vendor 'Xcalar, Inc.' --description 'Xcalar RHEL Mirror Repo' -C xcalar-rhel-mirror etc
	gsutil cp $@ gs://repo.xcalar.net/

upload-release: $(ALL)
	for ii in $^; do gsutil cp $$ii gs://repo.xcalar.net/; done
	for ii in $^; do gsutil -m setmeta -h "Cache-Control: $cache_control"  gs://repo.xcalar.net/$${ii}; done

