.PHONY: run all build deploy push nomad clean
SHELL = /bin/bash

IMAGE = registry.int.xcalar.com/xcalar/petname

run: build
	docker run -ti --rm -p 2015:2015 $(IMAGE)

all: deploy

petname: main.go
	go build -o $@ .

build: petname
	docker build -t $(IMAGE) .

push: build
	docker push $(IMAGE)

deploy: push
	nomad job plan petname.nomad
	nomad job run petname.nomad

clean:
	rm -f petname
	docker rmi registry.int.xcalar.com/xcalar/petname

