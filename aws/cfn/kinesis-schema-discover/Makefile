SHELL := /bin/bash

VENV = .venv
REQUIREMENTS = requirements.txt
CONSTRAINTS = constraints.txt
PYTHON = $(VENV)/bin/python
AWS = $(VENV)/bin/aws
SAM = $(VENV)/bin/sam
PYLINT = $(VENV)/bin/pylint
PYTEST = $(VENV)/bin/pytest

# Lambda vars
AWS_DEFAULT_REGION ?= us-west-2
#STACK_NAME ?= DiscoverSchemaStack
SAM_TEMPLATE = template.yaml
CFN_TEMPLATE = build/output.yaml
S3_LAMBDA_BUCKET = sharedinf-lambdabucket-559166403383-us-west-2

# Local conversion
TMP := $(shell mktemp -u s3://xcfield/tmp/discover-XXXXXX)
CSV1 = s3://xcfield/instantdatamart/tests/GlobalLandTemperaturesByCity_200lines.csv
JSON1 = s3://xcfield/instantdatamart/json/geneinfo_arr/xbq-arr
SAMPLEDATA = data/data.csv
SCHEMAS = $(patsubst %,%.schema.json,$(SAMPLEDATA))
SELECT = select.csv select.json

export AWS_DEFAULT_REGION #STACK_NAME

default: venv

all: $(SCHEMAS)

run: venv
	$(PYTHON) app.py $(CSV1) | jq -r .
	$(PYTHON) app.py $(JSON1) | jq -r .

	@echo "Discovering schema on $(TMP) ..."
$(VENV)-update: $(REQUIREMENTS) $(CONSTRAINTS)
	[ -e $(PYTHON) ] || /opt/xcalar/bin/python3.6 -m venv --clear --prompt $$(basename `pwd`) $(VENV)
	$(PYTHON) -m pip install -U pip setuptools wheel -c $(CONSTRAINTS)
	$(PYTHON) -m pip install -r $(REQUIREMENTS) -c $(CONSTRAINTS)
	touch $@

%.schema.json: % $(VENV)-update
	@$(AWS) s3 cp $< $(TMP)
	@echo "Discovering schema for $< ..."
	@$(PYTHON) app.py $(TMP) | jq -r . > `basename $(TMP)`
	@echo "Saved schema $@ ..."
	@mv `basename $(TMP)` $@
	@-$(AWS) s3 --quiet rm $(TMP)

clean:
	rm -f $(SCHEMAS) $(SELECT)

very-clean: clean
	rm -rf $(VENV)-update $(VENV)

venv: $(VENV)-update

check:
	$(PYLINT)

test: venv
	$(PYTEST)

deploy: venv
ifeq ($(STACK_NAME),)
  $(error Need to defined STACK_NAME)
endif
	$(SAM) package --template-file $(SAM_TEMPLATE) --output-template-file $(CFN_TEMPLATE) --s3-bucket $(S3_LAMBDA_BUCKET)
	$(SAM) deploy --template-file $(CFN_TEMPLATE) --stack-name $(STACK_NAME) --capabilities CAPABILITY_IAM

# Example select usage
select.json:
	aws s3api select-object-content --bucket xcfield --key instantdatamart/tests/readings_medium.csv.gz \
	    --input-serialization '{"CSV":{"FileHeaderInfo":"USE"}, "CompressionType" : "GZIP" }' \
	    --output-serialization '{"JSON":{}}' \
	    --expression-type SQL \
	    --expression "select \"id\",\"date\",\"zipcode\",\"ipAddress\" from s3object s where s.\"country\" LIKE '%Egypt%'" \
	    $@
	@head -10 $@

select.csv:
	aws s3api select-object-content --bucket xcfield --key instantdatamart/tests/readings_medium.csv.gz \
	    --input-serialization '{"CSV":{"FileHeaderInfo":"USE"}, "CompressionType" : "GZIP" }' \
	    --output-serialization '{"CSV":{}}' \
	    --expression-type SQL \
	    --expression "select \"id\",\"date\",\"zipcode\",\"ipAddress\" from s3object s where s.\"country\" LIKE '%Egypt%' LIMIT 5" \
	    $@
	@head -10 $@
