.PHONY: default build installer.json base gpu
SHELL = /bin/bash

TLD := $(shell git rev-parse --show-toplevel)
INSTALLER ?= /netstore/builds/ReleaseCandidates/xcalar-2.3.2-RC16/prod/xcalar-2.3.2-4754-installer
INSTALLER_URL ?= $(shell installer-url.sh -d gs $(INSTALLER))
CUDA_VERSION ?= 10.0

ifneq ($(BUILD_NUMBER),)
	EXTRA_VARS+= -var dash_build_number="-$(BUILD_NUMBER)"
endif

default: std

gcp.json: gcp.yaml
	cfn-flip < $< > $@

installer.json:
	installer-version.sh $(INSTALLER) > $@

base: gcp.json installer.json
	packer.io build $(FORCE) \
		-var packer_dir=$(TLD)/packer \
		-var installer_url="$(INSTALLER_URL)" \
		-var disk_size=20 \
		-var source_image_family=centos-7 \
		-var source_image=centos-7-v20200910 \
		-var-file installer.json \
		$(EXTRA_VARS) \
		-only=googlecompute-el7-base \
		gcp.json

gpu: gcp.json installer.json
	packer.io build $(FORCE) \
		-var installer_url="$(INSTALLER_URL)" \
		-var packer_dir=$(TLD)/packer \
		-var disk_size=60 \
		-var source_image_family=xcalar-el7-base \
		-var cuda_version=$(CUDA_VERSION) \
		-var-file installer.json \
		$(EXTRA_VARS) \
		-only=googlecompute-el7-gpu \
		gcp.json

std: gcp.json installer.json
	packer.io build $(FORCE) \
		-var installer_url="$(INSTALLER_URL)" \
		-var packer_dir=$(TLD)/packer \
		-var disk_size=60 \
		-var source_image_family=xcalar-el7-base \
		-var-file installer.json \
		$(EXTRA_VARS) \
		-only=googlecompute-el7-std \
		gcp.json

all: gcp.json installer.json
	packer.io build $(FORCE) \
		-var installer_url="$(INSTALLER_URL)" \
		-var packer_dir=$(TLD)/packer \
		-var disk_size=60 \
		-var source_image_family=xcalar-el7-base \
		-var-file installer.json \
		-except=googlecompute-el7-base \
		$(EXTRA_VARS) \
		-parallel-builds=0 \
		gcp.json

