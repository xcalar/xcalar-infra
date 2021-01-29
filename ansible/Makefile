SHELL = /bin/bash


INVENTORY_PY = inventory/vmware_inventory.py inventory/azure_rm.py inventory/docker.py inventory/ec2.py inventory/ovirt.py inventory/cobbler.py

ALL = $(INVENTORY_PY)

all: $(ALL)

clean:
	rm -f $(INVENTORY_PY)

inventory/%.py:
	curl -fsSL https://raw.githubusercontent.com/ansible/ansible/devel/contrib/inventory/$(@F) -o $@
	[[ $@ =~ .py$$ ]] && chmod +x $@ || :


