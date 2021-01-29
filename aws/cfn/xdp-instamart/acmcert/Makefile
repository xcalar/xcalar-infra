

ALL = $(glob *.py) requirements.txt
REGIONS ?= us-west-1 us-west-2 us-east-1 us-east-2
SHARED_LAMBDA_BUCKET ?= sharedinf-lambdabucket-559166403383
ZIP = lambda.zip
MD5 = $(shell md5sum $(ZIP) 2>/dev/null | cut -d' ' -f1)

default: $(ZIP)

$(ZIP): $(ALL)
	rm -rf .tmp
	mkdir -p .tmp
	pip install -t .tmp -r requirements.txt
	cp $^ .tmp
	cd .tmp && zip -9r ../$@ *
	ln $@ $(MD5).zip
	rm -rf .tmp

upload: $(ZIP)
	bn=$$(basename `pwd`); md5=$(MD5); echo /$${bn}/$${md5}.zip > key.txt; \
	   for r in $(REGIONS); do \
	    aws s3 cp --acl public-read lambda.zip s3://$(SHARED_LAMBDA_BUCKET)-$${r}/$${bn}/$${md5}.zip; \
	   done

clean:
	rm -fv $(MD5).zip $(ZIP)
