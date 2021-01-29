SHELL = /bin/bash

VM_NAME = ub18-template-1

ALL = ub18-vsphere.vm ub18-vmware.vm

default: ub18-vmware.vm

%.json: %.yaml
	cfn-flip < $< > $@

%.vm: vars.json %.json
	packer.io validate -var vm_name="$(VM_NAME)" -var-file $^
	packer.io build -force -machine-readable -debug -var vm_name="$(VM_NAME)" -var-file $^

clean:

