

all: scriptcs.tar.gz

scriptcs.tar.gz:
	docker build -t `basename $@ .tar.gz` .
	docker run --rm --entrypoint=/bin/bash `basename $@ .tar.gz` -c "cd /scriptcs/artifacts/Release/bin/ && tar czf - *" > $@.tmp
	mv $@.tmp $@


run: scriptcs.tar.gz
	docker run -e HOME=`pwd`/home -it -u `id -u`:`id -u` -v `pwd`:/data -w /data --rm scriptcs $(ARGS)
