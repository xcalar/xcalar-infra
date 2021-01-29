.PHONY: all default venv hooks upload clean recompile
SHELL:=/bin/bash


NETSTORE_NFS  ?= /netstore
NETSTORE_HOST ?= netstore
NETSTORE_IP   ?= 10.10.2.136

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))

ifeq ($(XLRINFRADIR),)
$(error Must set XLRINFRADIR. Please source .env file)
endif

VENV = .venv
PIP_FLAGS   ?= -q
REQUIRES     = requirements.txt
REQUIRES_IN  = requirements.in
HOOKS        = .git/hooks/pre-commit
PYTHON      ?= /opt/xcalar/bin/python3
TOUCH        = /usr/bin/touch
OSID        ?= $(shell osid)
PYVER       := $(shell $(PYTHON) -c "from __future__ import print_function; import sys; vi=sys.version_info; print(\"{}.{}\".format(vi.major,vi.minor))")
WHEELS      ?= /infra/wheels
UNIV_WHEELS := /infra/wheels/manylinux

PIP_FIND = --trusted-host $(NETSTORE_HOST) --trusted-host $(NETSTORE_IP) \
	--find-links http://$(NETSTORE_HOST)$(WHEELS)/index.html  --find-links http://$(NETSTORE_IP)$(WHEELS)/index.html

TOUCH ?= /usr/bin/touch

default: all

all: venv
	@echo "Run source .venv/bin/activate"

hooks: $(HOOKS)

$(HOOKS): scripts/hooks/pre-commit.sh
	ln -sfT ../../$< $@

venv: .updated

.updated: $(VENV)/bin/pip-compile $(REQUIRES)
	@echo "Syncing virtualenv in $(VENV) with packages in $(REQUIRES) ..."
	@$(VENV)/bin/python -m pip install -U pip
	@$(VENV)/bin/python -m pip install -U setuptools
	@$(VENV)/bin/python -m pip install -c $(REQUIRES) wheel pip-tools
	@if $(VENV)/bin/python -m pip show ansible 2>/dev/null | grep -q 'Version: 2.9'; then \
		rm -rf $(VENV)/lib/python*/site-packages/ansible/__init__.py; \
		$(VENV)/bin/python -m pip uninstall -y -q ansible; \
	fi
	@$(VENV)/bin/python -m pip install $(PIP_FIND) -r $(REQUIRES)
	@$(TOUCH) $@

sync:
	@$(VENV)/bin/pip-sync $(PIP_FIND) $(REQUIRES)

recompile: $(VENV)/bin/pip-compile
	$(VENV)/bin/pip-compile -v

upload: $(VENV)/bin/pip-compile
	$(VENV)/bin/pip wheel -w $(NETSTORE_NFS)$(WHEELS) -r $(REQUIRES) --exists-action i

$(VENV):
	@echo "Creating new virtualenv in $@ ..."
	@mkdir -p $@
	@deactivate 2>/dev/null || true; $(PYTHON) -m venv --prompt=$(shell basename $(current_dir)) $@
	@$(TOUCH) $@

$(VENV)/bin/pip-compile: $(VENV)
	@deactivate 2>/dev/null || true; $(VENV)/bin/python -m pip install $(PIP_FLAGS) -U pip
	@deactivate 2>/dev/null || true; $(VENV)/bin/python -m pip install $(PIP_FLAGS) -U setuptools
	@deactivate 2>/dev/null || true; $(VENV)/bin/python -m pip install $(PIP_FLAGS) -c requirements.txt wheel pip-tools
	@$(TOUCH) $@

clean:
	@echo Removing $(VENV) ...
	@rm -f .updated
	@if test -e $(VENV); then rm -r $(VENV); fi

# Used for running testing/verifying sources and json data
include mk/check.mk
include mk/convert.mk
-include local.mk
