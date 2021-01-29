SHELL=/bin/bash

all: vsts-token
	mkdir -p work{1..4}
	docker-compose up -d

vsts-token:
	vault read -format=json secret/vsts/worker-token  | jq -r .data.data > $@
	chmod 0400 $@
