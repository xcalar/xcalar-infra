
update:
	aws s3 cp --acl public-read test.yaml s3://xcrepo/playbooks/test.yaml
	aws cloudformation update-stack  --template-body file://`pwd`/linux-image.yaml --stack-name Ec2ImageBuilder --parameters ParameterKey=Playbook,ParameterValue=s3://xcrepo/playbooks/test.yaml --capabilities CAPABILITY_IAM

empty:
	aws cloudformation update-stack  --template-body file://`pwd`/linux-image-empty.yaml --stack-name Ec2ImageBuilder --capabilities CAPABILITY_IAM
