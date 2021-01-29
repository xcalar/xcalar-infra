getInstaller.zip: getInstaller.py requirements.txt
	mkdir workDir
	cp getInstaller.py workDir/
	pip install -r requirements.txt -t ./workDir
	(cd workDir; zip -r ../getInstaller.zip *)
	rm -rf ./workDir

.PHONY: all clean publish

publish: getInstaller.zip
	aws lambda delete-function --function-name getInstaller
	aws lambda create-function \
		--region us-west-2 \
		--function-name getInstaller \
		--zip-file fileb://getInstaller.zip \
		--role arn:aws:iam::559166403383:role/service-role/getInstaller \
		--handler getInstaller.lambda_handler \
		--runtime python2.7 \
		--timeout 15 \
		--memory-size 128

all: getInstaller.zip

clean:
	rm getInstaller.zip
