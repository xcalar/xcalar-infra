.PHONY: all clean deploy group deploy

SHELL = /bin/bash
V ?= 0

ifeq ($(V),0)
.SILENT:
endif

NOW = $(shell date +'%Y%m%d%H%M')

GROUP ?= $(shell id -un)-rg
LOCATION  ?= westus2
DEPLOY = $(GROUP)-deploy

ZONE ?= azure.xcalar.io
PARAMETERS ?= parameters.json
PARAMETERS_DEFAULTS ?= parameters.json.defaults
TEMPLATE ?= azuredeploy.json
S3CP= aws s3 cp --quiet
PUBLIC = --acl public-read --metadata-directive REPLACE --cache-control 'no-cache, no-store, must-revalidate, max-age=0, no-transform'
S3PUBLIC = $(S3CP) $(PUBLIC)

SCRIPTS_PATH=$(shell jq -r '[.variables.scriptsUri,.variables.customScriptName]|join("/")' mainTemplate.json | sed -e 's@^http://@@g')
SCRIPTS_SHA1=$(shell sha1sum $(BOOTSTRAP) | cut -d' ' -f1)

PAYLOAD = $(wildcard payload/*)

export GNUPGHOME=$(CURDIR)/.gnupg
JQ=/usr/local/bin/jq

s3url = $(shell aws s3 presign $(1))

-include local.mk

# These are the full URLs, possibly with parameter eg: https://xcrepo.s3.amazonaws.com/builds/foo.sh?Arg-1&Arg2=2
BOOTSTRAP_URL = https://s3-us-west-2.amazonaws.com/$(BUCKET)/$(S3_BOOTSTRAP_KEY)
INSTALLER_URL = $(call s3url, $(S3_INSTALLER))

JSON5 = $(wildcard *.json5)
JSON = $(patsubst %.json5,%.json,$(JSON5))

all: $(JSON)

%.json: %.json5
	@echo "Building $@ <- $<"
	json5 < $< > $@

%.json: %.yaml
	cfn-flip < $< > $@

lint:
	yamllint .

package: xdp-standard-package.zip

clean:
	rm -f xdp-standard-package.zip payload.tar.gz
	rm -rf .tmp

payload.tar.gz: $(PAYLOAD)
	@echo "Building $@ <- $^"
	rm -f $@
	fakeroot tar czf $@ $^

xdp-standard-package.zip: createUiDefinition.json mainTemplate.json bootstrap.sh payload.tar.gz
	@echo "Building $@ <- $^"
	rm -rf .tmp
	mkdir -p .tmp
	cp $^ .tmp
	rm -f $@
	(cd .tmp/ && zip -q ../$@ $^ && cp ../$@ .)

destroy:
	-az group delete --no-wait --name $(GROUP)
	@tail -1 local.mk | grep -q 'GROUP=$(GROUP)' && uniq local.mk | head -n-1 > local.mk.tmp && mv local.mk.tmp local.mk || true

check_bootstrap:
	@http_proxy=; \
     if ! test "`curl -sSL http://$(SCRIPTS_PATH) | sha1sum | cut -d' ' -f1`" = "$(SCRIPTS_SHA1)"; then \
        echo >&2 "ERROR: Checksum of $(BOOTSTRAP) doesn't match with what's referenced in your mainTemplate (http://$(SCRIPTS_PATH))"; \
        exit 1; \
     fi

update_bootstrap:
	@http_proxy=; \
    if test "`curl -o /dev/null -w '%{http_code}' -sSL http://$(SCRIPTS_PATH) 2>/dev/null`" != 200; then \
        gsutil cp $(BOOTSTRAP) gs://$(SCRIPTS_PATH); \
    elif test "`curl -sSL http://$(SCRIPTS_PATH) 2>/dev/null | sha1sum | cut -d' ' -f1`" = "$(SCRIPTS_SHA1)"; then \
        echo >&2 "http://$(SCRIPTS_PATH) already up-to-date"; \
    else \
        echo >&2 "http://$(SCRIPTS_PATH) already exists with a different checksum! Not overwriting! Bump the version in mainTemplate.json."; \
        exit 1; \
    fi

%.json: %.json.example
	@test -e $@ || { echo "Copying template $< to $@ ..." && cp $< $@ && echo "Please modify the missing sections in $(PARAMETERS) before redeploying!"; exit 1; }
	@touch $@

validateMain: $(VALIDATE_RG) parameters.json
	@bash -n $(BOOTSTRAP)
	@az deployment group validate --resource-group $(VALIDATE_RG) --template-file "mainTemplate.json" --parameters @parameters.main.json

validate: $(VALIDATE_RG) parameters.json
	@bash -n $(BOOTSTRAP)
	@aws s3 cp $(S3_BOOTSTRAP) - >/dev/null 2>&1 || aws s3 cp $(BOOTSTRAP) $(S3_BOOTSTRAP)
	@az deployment group validate --resource-group $(VALIDATE_RG) \
     --template-file "$(TEMPLATE)" \
     --parameters "$$(jq -r -s '.[0] * .[1] | .parameters | {\
                                           adminEmail, adminUsername, adminPassword, licenseKey, scaleNumber, dataDiskSize, vmSize,\
                                           dnsLabelPrefix: {value:"$(GROUP)"},\
                                           installerUrl: {value:"$(INSTALLER_URL)"},\
                                           bootstrapUrl: {value:"$(BOOTSTRAP_URL)"}\
                                           }|tojson' $(PARAMETERS_DEFAULTS) $(PARAMETERS))" --output json

deploy: $(GROUP) validate
	@(touch local.mk; cat local.mk; echo GROUP=$(GROUP)) | uniq | tee local.mk.tmp >/dev/null && mv local.mk.tmp local.mk
	time az deployment group create --resource-group $(GROUP) --name $(DEPLOY) \
     --template-file "$(TEMPLATE)" \
     --parameters "$$(jq -r -s '.[0] * .[1] | .parameters | {\
                                           adminEmail, adminUsername, adminPassword, licenseKey, scaleNumber, dataDiskSize, vmSize,\
                                           dnsLabelPrefix: {value:"$(GROUP)"},\
                                           installerUrl: {value:"$(INSTALLER_URL)"},\
                                           bootstrapUrl: {value:"$(BOOTSTRAP_URL)"}\
                                           }|tojson' $(PARAMETERS_DEFAULTS) $(PARAMETERS))"
	@echo "Your cluster is available at https://$$(az deployment group show --resource-group $(GROUP) --name $(DEPLOY) --output json --query 'properties.outputs.url.value' --output tsv)"

deployDev: $(GROUP) validate
	bash -n $(BOOTSTRAP)
	aws s3 cp $(S3_BOOTSTRAP) - >/dev/null 2>&1 || aws s3 cp $(BOOTSTRAP) $(S3_BOOTSTRAP)
	aws s3api put-object-acl --acl public-read --bucket $(BUCKET) --key $(S3_BOOTSTRAP_KEY)
	sed -i -e 's|"scriptsUri":.*$$|"scriptsUri": "'`dirname $(BOOTSTRAP_URL)`'",|g' applianceDevTemplate.json
	@(touch local.mk; cat local.mk; echo GROUP=$(GROUP)) | uniq | tee local.mk.tmp >/dev/null && mv local.mk.tmp local.mk
	time az deployment group create --resource-group $(GROUP) --name $(DEPLOY) \
     --template-file applianceDevTemplate.json \
     --parameters "$$(jq -r -s '.[0] * .[1] | .parameters | {\
                                           adminEmail, adminUsername, adminPassword, licenseKey, scaleNumber, vmSize,\
                                           dnsLabelPrefix: {value:"$(GROUP)"},\
                                           installerUrl: {value:"$(INSTALLER_URL)"},\
                                           bootstrapUrl: {value:"$(BOOTSTRAP_URL)"}\
                                           }|tojson' $(PARAMETERS_DEFAULTS) $(PARAMETERS))"
	@echo "Your cluster is available at https://$$(az deployment group show --resource-group $(GROUP) --name $(DEPLOY) --output json --query 'properties.outputs.url.value' --output tsv)"

deployMain: $(GROUP) validateMain
	time az deployment group create --resource-group $(GROUP) --name $(DEPLOY) \
     --template-file mainTemplate.json --parameters @parameters.main.json
	@echo "Your cluster is available at https://$$(az deployment group show --resource-group $(GROUP) --name $(DEPLOY) --output json --query 'properties.outputs.url.value' --output tsv)"

getips:
	@az vm list-ip-addresses --resource-group $(GROUP) --output json --query '[].virtualMachine.network.publicIpAddresses[].[name,ipAddress]' --output tsv

ssh: ssh/0 /usr/bin/sshpass
ssh/%:
	@sshpass -p "$(PASSWORD)" \
       ssh -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR \
       -l "$(USERNAME)" \
       `az vm list-ip-addresses --resource-group $(GROUP) --output json --query '[].virtualMachine.network.publicIpAddresses[].[name,ipAddress]' --output tsv | awk '/IP$(@F)/{print $$2}' $<`

# make certs/xdp-standard-001-099.tar.gz.gpg
.PRECIOUS: %.gpg
%.gpg: %
	cat $(GNUPGHOME)/password | gpg --no-use-agent --homedir=$(GNUPGHOME) --passphrase-fd=0 --armor --output=$@ --cipher-algo=AES256 --symmetric $<

.PRECIOUS: %.tar.gz
%.tar.gz: %.pem %.key
	fakeroot tar czvf $@ --transform='s,^$*,cert,' $^

%.gpg.upload: %.gpg
	$(S3PUBLIC) $< s3://xccerts/certs/$(ZONE)/bysha1/`sha1sum $< | cut -d' ' -f1`/$(<F)

%.upload: %.pem %.key
	$(S3PUBLIC) $(<F).pem s3://xccerts/certs/$(ZONE)/
	$(S3PUBLIC) $(<F).key s3://xccerts/certs/$(ZONE)/
