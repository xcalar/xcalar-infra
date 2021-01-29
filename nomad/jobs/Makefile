.PHONY: fabio

LEVANT = levant
DC ?= xcalar-sjc
DC_VARFILE ?= env/$(DC).yml
FABIO_VARFILE ?= env/fabio1514.yml

%.deploy: %.nomad
	if levant plan -var-file $(DC_VARFILE) $<; then \
       levant deploy -var-file $(DC_VARFILE) $<; fi

fabio: fabio-raw_exec.nomad
	if levant plan -var-file $(DC_VARFILE) -var-file $(FABIO_VARFILE) $<; then \
      levant deploy -var-file $(DC_VARFILE) -var-file $(FABIO_VARFILE) $<; fi
