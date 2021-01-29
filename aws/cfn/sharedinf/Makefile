SHELL = /bin/bash

ACLPUB = --acl public-read --metadata-directive 'REPLACE' --cache-control 'no-cache, no-store, must-revalidate, max-age=0, no-transform'
COPY = --content-disposition 'inline' $(ACLPUB)
BUCKET = xcrepo
BASE = cfn
STACK = sharedinf
LAMBDABASE = s3://$(BUCKET)/cfn/$(STACK)/
SHAREDINF_TEMPLATE = sharedinfrastructure.yaml
SHAREDINF_TEMPLATE_JSON = sharedinfrastructure.json
FTMPDIR := $(shell mktemp -u -t -d pip.XXXXXX)
PKGDIR := $(FTMPDIR)-pkg

CHANGE_NAME := update-$(STACK)-$(shell uuidgen)

# 559166403383
AWS_XCALAR_PROFILE ?= default
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text)
AWS_REGION ?= $(AWS_DEFAULT_REGION)
LAMBDABUCKET := $(STACK)-lambdabucket-$(AWS_ACCOUNT_ID)-$(AWS_REGION)
SHAREDINF_TEMPLATE_MD5SUM := $(shell md5sum $(SHAREDINF_TEMPLATE) | cut -d' ' -f 1)
SHAREDINF_TEMAPLTE_PATH = $(BASE)/$(STACK)/$(SHAREDINF_TEMPLATE_MD5SUM)
CHANGE_NAME := $(STACK)-change-$(shell uuidgen)
SHAREDINF_TEMPLATE_URL = https://$(BUCKET).s3.us-west-2.amazonaws.com/$(SHAREDINF_TEMAPLTE_PATH)/$(SHAREDINF_TEMPLATE_JSON)
.PHONY: $(STACK)

$(STACK):
	cfn-flip < $(SHAREDINF_TEMPLATE) | AWS_PROFILE=$(AWS_XCALAR_PROFILE) aws s3 cp $(COPY) - s3://$(BUCKET)/$(SHAREDINF_TEMAPLTE_PATH)/$(SHAREDINF_TEMPLATE_JSON)
	@echo "URL: $(SHAREDINF_TEMPLATE_URL)"

layer.zip: #requirements.txt constraints.txt
	mkdir -p $(FTMPDIR) $(PKGDIR) && python3.6 -m venv $(FTMPDIR) && source $(FTMPDIR)/bin/activate \
	    && python3 -m pip install -U pip setuptools wheel \
	    && python3 -m pip install -t $(PKGDIR) -r requirements.txt -c constraints.txt \
	    && pwd=`pwd` \
	    && cd $(PKGDIR) \
	    && zip -9r $${pwd}/$@.tmp . \
	    && cd - >/dev/null \
	    && rm -rf $(FTMPDIR) $(PKGDIR) \
	    && md5sum $@.tmp | cut -d' ' -f1 > $(@F).md5sum \
	    && MD5=`cat $(@F).md5sum` \
	    && sed -i 's@S3Key: .*$$@S3Key: sharedlibs/'$${MD5}'.zip@'  $(SHAREDINF_TEMPLATE) \
        && aws s3 cp $(ACLPUB) $@.tmp s3://$(LAMBDABUCKET)/sharedlibs/$${MD5}.zip \
        && mv $@.tmp $@

uploadzip: layer.zip
	md5sum $< | cut -d' ' -f1 > $(@F).md5sum \
	    && MD5=`cat $(@F).md5sum` \
	    && sed -i 's@S3Key: .*$$@S3Key: sharedlibs/'$${MD5}'.zip@'  $(SHAREDINF_TEMPLATE) \
		&& if [ "$$(curl -sS -I https://$(LAMBDABUCKET).s3.$(AWS_REGION).amazonaws.com/sharedlibs/$${MD5}.zip -o /dev/null -w '%{http_code}\n')" != 200 ]; then \
			aws s3 cp $(ACLPUB) $< s3://$(LAMBDABUCKET)/sharedlibs/$${MD5}.zip; \
		fi

noupdate: $(STACK)
	aws cloudformation update-stack --stack-name $(STACK) --template-url $(SHAREDINF_TEMPLATE_URL) --capabilities CAPABILITY_IAM --parameters "`cat ref/$@.parameters.json`"
	#aws cloudformation create-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK) --template-url https://$(BUCKET).s3-us-west-2.amazonaws.com/$(SHAREDINF_TEMAPLTE_PATH)/$(SHAREDINF_TEMPLATE_JSON) --capabilities CAPABILITY_IAM --parameters "`cat ref/$@.parameters.json`"

update: $(STACK) layer.zip
	subnet=$$(aws cloudformation describe-stacks --stack-name $(STACK) --query 'Stacks[0].Parameters[?ParameterKey==`vpccidr`].ParameterValue' --output text | cut -d. -f2); \
		   jinja2 -Dsubnet=$${subnet}  ref/$@.parameters.json.j2 > ref/$@.parameters.json
	aws cloudformation create-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK) --capabilities CAPABILITY_IAM --template-url $(SHAREDINF_TEMPLATE_URL) --parameters "`cat ref/$@.parameters.json`"
	aws cloudformation wait change-set-create-complete --change-set-name $(CHANGE_NAME) --stack-name $(STACK)  || (aws cloudformation describe-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK) --query StatusReason | grep 'Submit different information' && aws cloudformation delete-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK); exit 1)
	aws cloudformation describe-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK)
	sleep 10
	aws cloudformation execute-change-set --change-set-name $(CHANGE_NAME) --stack-name $(STACK)
	aws cloudformation wait stack-update-complete --stack-name $(STACK)
	if aws cloudformation describe-stack-events --stack-name $(STACK) --max-items 1 --query 'StackEvents[0].ResourceStatus' --output text | grep -E 'UPDATE_ROLLBACK_(COMPLETE|FAILED)'; then \
		exit 1; fi

deploy: $(STACK) layer.zip
	aws cloudformation create-stack --stack-name $(STACK) --template-url $(SHAREDINF_TEMPLATE_URL) --parameters "`cat ref/update.parameters.json`"
