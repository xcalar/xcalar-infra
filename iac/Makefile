.PHONY: aws gcp

AWS_ACCOUNT_ID ?= 559166403383
GCP_PROJECT ?= angular-expanse-99923
GCP_REGION ?= us-central1


terraform:
	curl -f -L -O https://releases.hashicorp.com/terraform/0.12.29/terraform_0.12.29_linux_amd64.zip
	unzip terraform*.zip
	mkdir -p $${HOME}/bin
	mv terraform $${HOME}/bin/

aws:
	aws sts get-caller-identity
	PATH=$${HOME}/bin:$${PATH} terraformer import aws --path-output aws/aws-$(AWS_ACCOUNT_ID) -r vpc,subnet,nacl,iam,route53,s3,lambda

gcp:
	PATH=$${HOME}/bin:$${PATH} terraformer import google --projects=$(GCP_PROJECT) --path-output=gcp/ --regions=$(GCP_REGION) --resources=images,instances,dns  -v
