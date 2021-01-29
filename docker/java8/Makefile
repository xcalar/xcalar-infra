
SHELL = /bin/bash

JAVA ?= 11

DOCKER_MOUNTS=-v $(PWD):$(PWD) -w $(PWD)
UID = $(shell id -u):$(shell id -g)

default: run

%.class: %.java
	javac $< $>

run: MemoryEater.java
	javac MemoryEater.java
	docker run $(DOCKER_MOUNTS) -u $(UID) -it --rm --memory=512m  openjdk:$(JAVA) ./java-cmd -Xmx512M  MemoryEater
