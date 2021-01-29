# Make file for Xcalar Management Console
# 1- Create temporary directories for build.
# 2- Pull XMC source code from git repo 
# 3- Replace placeholder variables in source code
# 4- Zip lambda codes in zip files (required by cfn template)
# 5- Upload everything to given bucket
# After this make file is successfully run , two cfn templates are uploaded to:
# s3://$(BUCKET_NAME)/xmc/dep.yaml
# s3://$(BUCKET_NAME)/xmc/dep_ui.yaml
#
# To install XMC , customer should run these two cloudformation templates (firt dep.yaml then dep_ui.yaml)
# If everything goes well a new directory 3://$(BUCKET_NAME)/xmc/ui should be created with ui files
# Once Xcalar reference bucket has all files in it , policy below shoul be added to bucket policies.
# This policy allows customer account to copy files from xcalar bucket to their own bucket (cross bucket permissions)
# simply replace CUSTOMER_ACCOUNT_NUMBER with customer account and attach the policy to Xcalar reference bucket
#{
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Sid": "Example permissions",
#            "Effect": "Allow",
#            "Principal": {
#                "AWS": "arn:aws:iam::CUSTOMER_ACCOUNT_NUMBER:root"
#            },
#            "Action": [
#                "s3:GetBucketLocation",
#                "s3:ListBucket"
#            ],
#            "Resource": "arn:aws:s3:::abilgintest"
#        }
#    ]
#}

TABLE_NAME = xmc_table#<< DYNAMO TABLE NAME , just leave it as is unless multiple instances of the tool needed on one AWS account
BUCKET_NAME = abilgintest# << Xcalar reference bucket, customer should have the exact same structure and content in their own bucket
VERSION = 1
REGION = us-west-2# Region of the reference s3 bucket, it is used by script to build path of cfn yaml files
# STEP 5 - Copy everything to Xcalar reference bucket
finalize: stage
	aws  s3 cp --recursive --acl public-read ./stage/xmc s3://$(BUCKET_NAME)/xmc
	
# STEP 1 - Create Temporary directories
directories : 
	rm -rf ./stage
	rm -rf ./client  
	rm -rf ./source_base
	rm -rf ./package
	mkdir stage
	mkdir stage/xmc
	mkdir source_base
	mkdir source_base/ui
	
# STEP 2 - pull source code from git , extract it #FIXME : right now it copies files from my local disk 
copy_source : directories
	cp -r ../templates ./source_base
	cp -r ../lambda ./source_base/lambda
	cp -r ../ui/* ./source_base/ui

# STEP 3 - copy source code to temporary folders , replace dynamo table names in source code with given instance name
sed_ops : copy_source
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/lambda/getFromDB.js > ./stage/xmc/getFromDB.js
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/lambda/postToDB.js > ./stage/xmc/postToDB.js
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/lambda/createCluster.js > ./stage/xmc/createCluster.js
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/lambda/deleteCluster.js > ./stage/xmc/deleteCluster.js
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/lambda/listClusters.js > ./stage/xmc/listClusters.js
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/templates/dep.yaml.template > ./stage/xmc/dep.yaml
	sed 's/XMC_TABLE_NAME/$(TABLE_NAME)/g' ./source_base/templates/dep_ui.yaml.template > ./stage/xmc/dep_ui.yaml
	cp ./source_base/templates/cfn_template ./stage/xmc
	cp -r ./source_base/ui ./stage/xmc
	rm -rf ./stage/xmc/ui/node_modules 
		
# STEP 4 - create zip files for lambdas , clean up rest
stage : sed_ops
	zip -j ./stage/xmc/createCluster.zip ./stage/xmc/createCluster.js ./stage/xmc/cfn_template
	zip -j ./stage/xmc/listClusters.zip ./stage/xmc/listClusters.js
	zip -j ./stage/xmc/deleteCluster.zip ./stage/xmc/deleteCluster.js
	zip -j ./stage/xmc/postToDB.zip ./stage/xmc/postToDB.js
	zip -j ./stage/xmc/getFromDB.zip ./stage/xmc/getFromDB.js
	rm ./stage/xmc/*.js
	rm ./stage/xmc/cfn_template	

    	