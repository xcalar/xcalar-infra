SHELL=/bin/bash

ifeq ($(RESOURCE_GROUP),)
    $(error Must specify RESOURCE_GROUP)
endif

ifeq ($(VMSSNAME),)
    $(error Must specify VMSSNAME)
endif

ifeq ($(TEMPLATE),)
    $(error Must specify TEMPLATE)
endif

$(RESOURCE_GROUP)/nomadvmss.json: template/azuredeploy.yaml
	mkdir -p $(@D)
	yarm -i $< -o $@

$(RESOURCE_GROUP)/nomadvmss.cloud-init.yaml: template/cloud-init-secure.yaml.j2 nomadvmss.yaml
	mkdir -p $(@D)
	jinja2 $^ > $@

$(RESOURCE_GROUP)/nomadvmss.parameters.yaml: template/azuredeploy.parameters.yaml.j2 nomadvmss.yaml
	mkdir -p $(@D)
	jinja2 $^ > $@

$(RESOURCE_GROUP)/nomadvmss.parameters.json: $(RESOURCE_GROUP)/nomadvmss.parameters.yaml
	mkdir -p $(@D)
	yarm -i $< -o $@

$(RESOURCE_GROUP)/nomadvmss.azuredeploy.json: template/azuredeploy.yaml
	mkdir -p $(@D)
	yarm -i $< -o $@

%.json: %.yaml
	mkdir -p $(@D)
	yarm -i $< -o $@

validate: $(RESOURCE_GROUP)/nomadvmss.azuredeploy.json $(RESOURCE_GROUP)/nomadvmss.parameters.json $(RESOURCE_GROUP)/nomadvmss.cloud-init.yaml
	az deployment group validate \
	    -g $(RESOURCE_GROUP) \
	    --template-file $(RESOURCE_GROUP)/nomadvmss.azuredeploy.json \
        --parameters \
        @$(RESOURCE_GROUP)/nomadvmss.parameters.json \
        vmssName=$(VMSSNAME) \
        customData="$$(gzip -c nomadvmss.cloud-init.yaml | base64 -w0)"

deploy: validate
	az deployment group create --name deploy-`date +'%Y%m%d%H%S'` \
	    -g $(RESOURCE_GROUP) \
	    --template-file $(RESOURCE_GROUP)/nomadvmss.azuredeploy.json \
        --parameters \
        @$(RESOURCE_GROUP)/nomadvmss.parameters.json \
        vmssName=$(VMSSNAME) \
        customData="$$(gzip -c nomadvmss.cloud-init.yaml | base64 -w0)"
