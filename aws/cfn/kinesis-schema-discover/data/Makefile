SHELL := /bin/bash

BUCKET = xcfield
TOPDIR = instantdatamart/tests
S3TOP = s3://$(BUCKET)
S3URI = $(S3TOP)/$(TOPDIR)
HTTPSTOP = https://$(BUCKET).s3.amazonaws.com
HTTPSURI = $(HTTPSTOP)/$(TOPDIR)
TMP := $(shell mktemp -u -t s3sync.XXXXXX)

all:
	@echo "usage: "
	@echo "  upload    - upload local data csv/json files to $(S3URI)/"
	@echo "  download  - download data from $(S3URI)/"

upload:
	aws s3 sync ./ $(S3URI)/ --acl public-read --exclude '*' --include '*.csv*' --include '*.json*' --exclude '*.schema.json'
	aws s3 ls $(S3URI)/ --recursive | awk '{print $$(NF)}' | grep -v MANIFEST > MANIFEST.keys
	sed 's@^@$(S3TOP)/@g' MANIFEST.keys > MANIFEST.s3uri
	sed 's@^@$(HTTPSTOP)/@g' MANIFEST.keys > MANIFEST.https
	aws s3 cp --acl public-read MANIFEST.s3uri $(S3URI)/MANIFEST
	aws s3 sync ./ $(S3URI)/ --acl public-read

download:
	aws s3 sync $(S3URI)/ ./
