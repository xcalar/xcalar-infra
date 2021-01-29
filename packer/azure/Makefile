SHELL = /bin/bash

VERSION ?= $(shell date '+%Y.%m.%d')
BUILD_NUMBER ?= 1
INSTALLER ?=

default: jenkins.azure

all: jenkins.azure devstation.azure infra.azure

%.json: %.yaml
	cfn-flip < $< > $@

build.json: build.yaml

%.azure: build.json %.json
	chmod 0600 ../ssh/*.pem
	packer.io validate \
		-var version=$(VERSION) -var build_number=$(BUILD_NUMBER) \
		-var-file <(vault kv get -format=json -field=data secret/azure/packer-sp) \
		$(patsubst %.json,-var-file %.json,$(filter-out $<,$^)) $<
	packer.io build \
		-force \
		-var version=$(VERSION) -var build_number=$(BUILD_NUMBER) \
		-var-file <(vault kv get -format=json -field=data secret/azure/packer-sp) \
		$(patsubst %.json,-var-file %.json,$(filter-out $<,$^)) $<

installer.azure: installer.json
	chmod 0600 ../ssh/*.pem
	packer.io validate \
		-var version=$(VERSION) -var installer_url="$$(installer-url.sh -d az $(INSTALLER))" -var build_number=$(BUILD_NUMBER) \
		-var-file <(vault kv get -format=json -field=data secret/azure/packer-sp) \
		$(patsubst %.json,-var-file %.json,$(filter-out $<,$^)) $<
	packer.io build \
		-force \
		-var version=$(VERSION) -var installer_url="$$(installer-url.sh -d az $(INSTALLER))" -var build_number=$(BUILD_NUMBER) \
		-var-file <(vault kv get -format=json -field=data secret/azure/packer-sp) \
		$(patsubst %.json,-var-file %.json,$(filter-out $<,$^)) $<
