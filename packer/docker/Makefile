.PHONY: default docker-base-el7 docker-xcalar-el7 test
SHELL = /bin/bash

-include local.mk

INSTALLER ?= /netstore/builds/byJob/BuildTrunk/xcalar-latest-installer-prod
INSTALLER_VARS = installer_vars.json
INSTALLER_VERSION = $(shell jq -r .installer_version $(INSTALLER_VARS))
PROJECT ?= xdp-instamart
PACKER_LOG := 1
PACKER_LOG_PATH := packer.log
PACKER_BIN ?= packer.io
REGISTRY ?= localhost:5000
YAMLLIBS = $(wildcard lib/*.lib.yml)  # YAML libraries.. that's a thing now
ARGS = -var-file=vars/ssh.json \
	   -var http_proxy="$(http_proxy)" -var no_proxy="$(no_proxy)" \
	   -var installer="$(INSTALLER)" -var-file=$(INSTALLER_VARS) \
	   -var registry=$(REGISTRY)

ifneq ($(JENKINS_URL),)
	PACKER_NO_COLOR=1
endif

export PROJECT PACKER_LOG PACKER_LOG_PATH CHECKPOINT_DISABLE=1 PACKER_NO_COLOR

default: docker-xcalar-el7

%.json: %.yaml $(YAMLLIBS)
	set -o pipefail; ytt $(patsubst %,-f %,$^) | cfn-flip | jq -r . > $@.tmp && mv $@.tmp $@

.PHONY: $(INSTALLER_VARS)
$(INSTALLER_VARS):
	installer-version.sh --format=json "$(INSTALLER)" > $@.tmp && mv $@.tmp $@

test: test.json
	packer.io validate $<
	packer.io build $<

docker-xcalar-el7: docker.json $(INSTALLER_VARS)
	packer.io validate $(ARGS) -only=$@ $<
	packer.io build $(ARGS) -var repository='xcalar/xcalar' -only=$@ $<

docker-base-el7: docker.json $(INSTALLER_VARS)
	jq -r '.installer_tag="$(INSTALLER_VERSION)"' < $(INSTALLER_VARS) > tmp.json && mv tmp.json $(INSTALLER_VARS)
	packer.io validate $(ARGS) -only=$@ $<
	packer.io build $(ARGS) -var repository='xcalar/base' -var "installer_tag=`jq -r .installer_version $(INSTALLER_VARS)`" -only=$@ $<

%.yaml: %.yaml.j2
	e2j2 --block_start '[%%' --block_end '%%]' --variable_start '[[' --variable_end ']]' -f $<
