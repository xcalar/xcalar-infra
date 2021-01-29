
build:
	docker build -t registry.int.xcalar.com/awscliv2:latest -f Dockerfile $(XLRINFRADIR)

push: build
	docker push registry.int.xcalar.com/awscliv2:latest
