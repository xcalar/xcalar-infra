.PHONY: all build deploy clean package venv

SHELL = /bin/bash

APP = ondemand
S3BUCKET = xcondemand
S3PREFIX =
STACK = xcondemand
OUTPUT = sam-output-template.yaml
TEMPLATE = template.yaml
REQ = requirements.txt
PY_SOURCES = ondemand/app.py
SOURCES = $(REQ) $(PY_SOURCES)
BUILD = $(APP)/build
SAM = .venv/bin/sam

ENDPOINT ?= http://127.0.0.1:3000/v1/cluster

VENV = .venv

venv: $(VENV)/.updated

$(VENV):
	rm -rf $(VENV)
	virtualenv $(VENV)

$(VENV)/.updated: $(VENV) requirements_dev.txt
	$(VENV)/bin/pip install -q -r requirements_dev.txt
	touch $@

$(BUILD)/.updated: $(SOURCES)
	mkdir -p $(@D)
	#pip3 install -r $(REQ) -t $(@D)
	cp $(APP)/*.py $(@D)
	touch $@

package: $(BUILD)/.updated
	$(SAM) validate
	$(SAM) package --template-file $(TEMPLATE) --output-template-file $(OUTPUT) --s3-bucket $(S3BUCKET)

deploy: package
	$(SAM) validate
	$(SAM) deploy --template-file $(OUTPUT) --stack-name $(STACK) --s3-bucket $(S3BUCKET) --s3-prefix '$(S3PREFIX)' --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --no-fail-on-empty-changeset --parameter-overrides S3Bucket=$(S3BUCKET) S3Prefix='$(S3PREFIX)' `cat parameters/overrides.txt` AllowedCIDR=`curl -4 -s https://checkip.amazonaws.com`/32


server:
	$(SAM) local start-api --skip-pull-image --profile default -t template.yaml --debug

request:
	curl -v -H 'Content-type: application/json' -X PUT '$(ENDPOINT)?count=1&foo=bar&command=create_cluster' -d '{}'

# Alternate way to invoke fn
invoke:
	$(SAM) local invoke --skip-pull-image --profile default  --no-event OnDemandFunction

all:
	$(MAKE) -s clean
	$(MAKE) -s deploy

clean:
	test -d $(BUILD) && rm -r $(BUILD) || true


portal:
	aws --profile=vtest s3 cp portal-1234.html s3://portalbucketanduser-portalbucket-6xwvqoasv799/
	#aws --profile=vtest s3 cp s3://portalbucketanduser-portalbucket-6xwvqoasv799/
