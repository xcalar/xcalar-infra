.PHONY: all check clean upload create deploy update lambda
SHELL       := /bin/bash
TOP         := $(patsubst %/,%,$(dir $(realpath $(firstword $(MAKEFILE_LIST)))))

SHADOW_BASE := /tmp/$(shell id -u)/shadow
SHADOW      := $(SHADOW_BASE)$(TOP)

PACKER_JSON ?= $(XLRINFRADIR)/output/packer-manifest.json

## Way too slow
# LAST_UUID   := $(shell jq -r ".last_run_uuid" $(PACKER_JSON))
# AMI_ID      := $(shell jq -r '.builds[]|select(.name == "amazon-ebs-amzn2")|select(.packer_run_uuid == "$(LAST_UUID)") .artifact_id' $(PACKER_JSON) | cut -d':' -f 2)

PROJECT     = $(notdir $(TOP))
LAMBDAS     = lambda/add_notification.py lambda/schedule.py
LAMBDA_KEY := $(shell md5sum $(LAMBDAS) | md5sum | cut -d' ' -f1)
LAMBDA_ZIP := $(LAMBDA_KEY)-lambda.zip
SHADOW_LAMBDA_ZIP := $(SHADOW)/$(LAMBDA_ZIP)
GEN         = $(SHADOW)/xdp-standard.cf.yaml $(SHADOW)/stepfun.cf.yaml
VARS        := $(wildcard vars/*.yaml)
TEMPLATES   = $(patsubst %.cf.yaml, %.template, $(GEN))
JSONS       = $(patsubst %.template, %.json, $(TEMPLATES))
VALIDATION  = $(patsubst %.template, %.valid, $(TEMPLATES))
PARAMS      = $(patsubst %.valid, %.params, $(VALIDATION))
DEBUG       ?= 0
ENVIRONMENT ?= test
AWS_DEFAULT_REGION = us-west-2
ALL_REGIONS  = us-west-2 us-east-1 us-east-2 us-west-1
REGIONS     ?= $(AWS_DEFAULT_REGION)
AWS_ACCOUNT  = 559166403383
S3FLAGS      = --cache-control 'private, no-cache, no-store, must-revalidate, max-age=0, no-transform' --acl public-read --metadata-directive REPLACE
SOURCES      = $(SHADOW)/xdp-standard.template $(SHADOW)/stepfun.template scripts/user-data.sh scripts/batch.sh

LAMBDA_BUCKET_PREFIX = sharedinf-lambdabucket-$(AWS_ACCOUNT)
LAMBDA_BUCKET        = $(LAMBDA_BUCKET_PREFIX)-$(AWS_DEFAULT_REGION)

URL          = ref/output.url
UUID        := $(shell uuidgen)
CHANGE_SET   = mychange-$(UUID)
NAME        := $(shell id -un)
STACK_NAME   = $(NAME)-instamart
BASEURL     := $(shell baseurl.sh `installer-version.sh --format=cli $(AMI_ID)` --env $(ENVIRONMENT) --project $(PROJECT))

all: check
	echo "$(SHADOW)"
	echo "$(SHADOW_BASE)"
	echo "$(TOP)"
	echo "$(PROJECT)"
	echo "$(LAMBDA_KEY)"

check: $(GEN) $(VALIDATION) $(PARAMS) $(JSONS)
	$(Q)mkdir -p $(@D)
	$(Q)yamllint -c $(XLRINFRADIR)/.yamllint $(SHADOW)/*.cf.yaml
	$(Q)cfn-lint $(SHADOW)/*.cf.yaml

%.valid: %.template
	$(Q)mkdir -p $(@D)
	$(Q)echo "Cfn-linting $< ..."
	$(Q)cfn-lint $<
	$(Q)echo "Verifying template with AWS $< ..."
	$(Q)aws cloudformation validate-template --template-body file://$< > $@.tmp
	@mv $@.tmp $@

%.params: %.valid
	mkdir -p $(@D)
	jq -r '[.Parameters[]|{ParameterKey:.ParameterKey, UsePreviousValue: true}]' $< > $@.tmp
	@mv $@.tmp $@

clean:
	rm -fv $(TEMPLATES) $(GEN) $(VALIDATION) $(PARAMS) $(JSONS)

$(SHADOW)/xdp-standard.cf.yaml: $(SHADOW)/stepfun.json

constraints.txt: requirements.txt
	pip-compile -v -o $@ $<

%.json: %.cf.yaml
	mkdir -p $(@D)
	cfn-flip -c < $^ > $@.tmp
	@mv $@.tmp $@

$(PACKER_JSON):
	curl -fsSL https://jenkins.int.xcalar.com/job/Packer/lastSuccessfulBuild/artifact/output/packer-manifest.json -o $@

$(SHADOW)/last_uuid: $(PACKER_JSON)
	mkdir -p $(@D)
	jq -r ".last_run_uuid" $(PACKER_JSON) > $@.tmp && mv $@.tmp $@

$(SHADOW)/ami_id: $(SHADOW)/last_uuid
	@mkdir -p $(@D)
	LAST_UUID=`cat $<` && \
       jq -r '.builds[]|select(.name == "amazon-ebs-amzn2")|select(.packer_run_uuid == "'$${LAST_UUID}'") .artifact_id' $(PACKER_JSON) | cut -d':' -f 2 > $@.tmp && mv $@.tmp $@

$(SHADOW)/ami.json: $(SHADOW)/ami_id
	set -o pipefail; aws ec2 describe-images --image-ids `cat $<` --query 'Images[].Tags[]' | jq '{ami: map_values({(.Key): .Value})|add}' > $@.tmp && mv $@.tmp $@

$(SHADOW)/installer.clieq: $(SHADOW)/ami_id
	installer-version.sh --format=clieq $$(cat $<) > $@.tmp && mv $@.tmp $@

%.cf.yaml: %.template
	aws cloudformation package --s3-bucket $(LAMBDA_BUCKET) --s3-prefix $(PROJECT) --template-file $< --output-template-file $@

$(SHADOW)/%.template: %.template.j2 $(SHADOW)/ami_id
	mkdir -p $(@D)
	set -o pipefail; cat $(VARS) ../flavor/default.yaml | jinja2 -DforSam=True -Dlambdabucket=$(LAMBDA_BUCKET) -DbaseUrl=$(BASEURL) -DbootstrapUrl=$(BASEURL)/scripts/user-data.sh -DDEBUG=$(DEBUG) -Dami_id=`cat $(SHADOW)/ami_id` $< > $@.tmp && mv $@.tmp $@

$(SHADOW)/lambda.md5: $(LAMBDAS)
	md5sum $^ > $@sums
	md5sum $@sums > $@

$(SHADOW_LAMBDA_ZIP): $(LAMBDAS)
	mkdir -p $(@D)
	rm -f $@
	cd lambda && zip -9r $@ $(notdir $^)

lambda: vars/lambdakey.yaml

vars/lambdakey.yaml: $(SHADOW_LAMBDA_ZIP)
	lambda-function.sh --all-regions --regionless-bucket $(LAMBDA_BUCKET_PREFIX) --key $(PROJECT)/$(LAMBDA_ZIP) --file $<
	echo "lambdakey: $(PROJECT)/$(LAMBDA_ZIP)" > $@.tmp && mv $@.tmp $@

upload: $(SHADOW)/installer.clieq vars/lambdakey.yaml
	dc2 upload --debug --keep --project $(PROJECT) --env $(ENVIRONMENT) --manifest $(PACKER_JSON) $$(cat $<) --url-file $(URL)

STACK_CHANGE = --stack-name $(STACK_NAME) --change-set-name $(CHANGE_SET)
create: check upload
	aws cloudformation create-stack --stack-name $(STACK_NAME) --template-url $$(grep xdp-standard $(URL)) --parameters file://ref/$(NAME).params.json --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND

deploy: $(SHADOW)/xdp-standard.cf.yaml vars/lambdakey.yaml
	aws cloudformation create-change-set $(STACK_CHANGE) --template-body file://$< --parameters file://ref/$(NAME).params.json --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
	aws cloudformation wait change-set-create-complete $(STACK_CHANGE)
	aws cloudformation describe-change-set $(STACK_CHANGE) | tee ref/$(STACK_NAME)-$(CHANGE_SET).change
	aws cloudformation execute-change-set $(STACK_CHANGE)
	aws cloudformation wait stack-update-complete --stack-name $(STACK_NAME)

update: $(TEMPLATES)
	$(MAKE) CHANGE_SET=change-`uuidgen` check upload deploy
