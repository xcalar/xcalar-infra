
SANDBOXTAR=HDP_2.5_docker.tar
SANDBOXURL=https://hortonassets.s3.amazonaws.com/2.5/$(SANDBOXTAR).gz
LOCALCACHE=/netstore/applications/HDP

$(SANDBOXTAR):
	test -e $(LOCALCACHE)/$@ && cp $(LOCALCACHE)/$@ $@.tmp || curl -fsSL $(SANDBOXURL) | gzip -dc > $@.tmp
	mv $@.tmp $@

all: $(SANDBOXTAR)
	docker images -q sandbox || docker load < $<
	curl -sSL https://github.com/hortonworks/tutorials/raw/hdp-2.5/tutorials/hortonworks/hortonworks-sandbox-hdp2.5-guide/start_sandbox.sh > start_sandbox.sh
	bash ./start_sandbox.sh
	ssh -oPort=2222 root@localhost # password = 'hadoop'
	echo "Run: ssh -oPort=2222 root@localhost ambari-admin-password-reset"
