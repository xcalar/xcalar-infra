# verbose
V = 0

V_CMD := $(if $(filter 0,$(V)),@,)

VALIDATE_EXT_AUTO := sh json yaml yml
VALIDATE_TARGETS := $(foreach v,$(VALIDATE_EXT),validate.$(v))

FIND := find
FIND_ARGS := $(foreach v,$(VALIDATE_EXT_AUTO),-name '*.$(v)' -o) -false
D_ = $(shell $(FIND) azure aws gce ansible bin scripts $(FIND_ARGS))
D := $(filter-out $(SUBMODULE_PATTERNS),$(D_))

D_JSON := $(filter %.json,$(D))
D_SH := $(filter %.sh,$(D))
D_YAML := $(filter %.yaml,$(D))
D_YML := $(filter %.yml,$(D))

VALIDATE_JSON := $(D_JSON)
VALIDATE_SH   := $(D_SH)
VALIDATE_YAML := $(D_YAML)
VALIDATE_YML  := $(D_YML)

LINT_TARGETS := $(foreach v,$(VALIDATE_EXT_AUTO),lint.$(v))
ALL_CHECKS := $(LINT_TARGETS) #$$(VALIDATE_TARGETS)
EXCLUDE_CHECKS :=
CHECKS := $(filter-out $(EXCLUDE_CHECKS),$(ALL_CHECKS))

LINT.SH := bash -n
LINT.JSON := jq -r .
LINT.YAML := yamllint -c $(XLRINFRADIR)/.yamllint #$(VIRTUAL_ENV)/bin/cfn-flip
LINT.YML  := yamllint -c $(XLRINFRADIR)/.yamllint #$(VIRTUAL_ENV)/bin/cfn-flip
ECHO := /bin/echo


define GEN_tool

bin/$(1): bin/$(1)-$(2)
	ln -sfnr $$< $$@

bin/$(1)-$(2):
	curl -fL http://repo.xcalar.net/deps/$(1)-$(2)-`uname -s`.tar.gz | tar zxfv - -C $$(@D)

TOOLS += bin/$(1)

endef

#$(info $(call GEN_tool,shfmt,2.1.0))
$(eval $(call GEN_tool,shfmt,2.2.1))
#TOOLS += $(VIRTUAL_ENV)/bin/shfmt-2.1.0
#$(foreach PROGRAM,shfmt-2.1.0,$(info $(call GEN_tool,$(PROGRAM))))

#define GEN_validate
#
#$(1)-up := $(shell echo $(1) | tr a-z A-Z)
#
#lint.$(1): $$(D_$(eval $(1)_up))
#ifneq ($(strip $$(D_$(eval $(1)_up))
#	\$(V_CMD)for i in \$(^); do \
#        \$(ECHO) "(LINT.$(eval $(1)_up) $$$$i" >&2 ; \
#        \$(LINT.$(eval $(1)_up)) $$$$i >/dev/null ; \
#    done
#endif
#
#endef
#
#$(foreach shext,$(VALIDATE_EXT_AUTO),$(eval $(call GEN_validate,$(shext))))
#
#$(eval $(call GEN_validate,sh))

validate:  $(CHECKS)
	$(ECHO) $<

check: $(TOOLS) $(CHECKS) all


lint.sh: $(D_SH)
ifneq ($(strip $(D_SH)),)
	$(V_CMD)for i in $(^); do \
        $(ECHO) "(LINT.SH) $$i" >&2 ; \
        $(LINT.SH) $$i >/dev/null ; \
    done
else
	@true
endif


lint.json: $(D_JSON)
ifneq ($(strip $(D_JSON)),)
	$(V_CMD)for i in $(^); do \
        $(ECHO) "(LINT.JSON) $$i" >&2 ; \
        $(LINT.JSON) $$i >/dev/null ; \
    done
else
	@true
endif


lint.yml: $(D_YML)
ifneq ($(strip $(D_YML)),)
	$(V_CMD)for i in $(^); do \
        $(ECHO) "(LINT.YML) $$i" >&2; \
        $(LINT.YML) $$i || exit; \
    done
else
	@true
endif

lint.yaml: $(D_YAML)
ifneq ($(strip $(D_YAML)),)
	$(V_CMD)for i in $(^); do \
        $(ECHO) "(LINT.YAML) $$i" >&2; \
        $(LINT.YAML) $$i || exit; \
    done
else
	@true
endif

