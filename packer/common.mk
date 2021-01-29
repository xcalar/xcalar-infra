.PHONY: all ubuntu gce aws cloud vmware qemu el7-qemu

PACKER_BUILD ?= time packer build -force -on-error=abort

all_top:
	@echo arguments:
	@echo   aws
	@echo   gce
	@echo   vmware
	@echo   qemu

%.json: %.yaml
	cfn-flip < $< > $@

el7-qemu: el7-qemu.json
	$(PACKER_BUILD) -only=$@ $<

box/jenkins-slave-ub14-20161020.ova: vmware

vmware:
	$(PACKER_BUILD) -only=vmware-iso ub14-vmware-qemu.json

gce:
	$(PACKER_BUILD) -only=googlecompute ub14-cloud.json

aws:
	$(PACKER_BUILD) -only=amazon-ebs -var-file=$(HOME)/.packer-vars ub14-cloud.json

cloud:
	$(PACKER_BUILD) -var-file=$(HOME)/.packer-vars ub14-cloud.json

box/%.ova:
	ovftool -dm=thin --name="$(@F)" --compress=1 output-vmware/packer-vmware-iso.vmx $@

xcalar-build-context.tar.gz:
	dir=$$(pwd) && cd $$XLRDIR && $$(sh -c 'command -v fakeroot || true') tar czvf $$dir/xcalar-build-context.tar.gz $$(egrep '(COPY|ADD)' docker/ub14/ub14-build/Dockerfile  | awk '{print $$2}')
	now=$$(date +'%s'); file=xcalar-build-context-$$now.tar.gz; gsutil cp $@ gs://repo.xcalar.net/deps/$$file && sed -i -e 's/xcalar-build-context.*.tar.gz/'$$file'/g' scripts/provision-*.sh
