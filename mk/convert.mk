SHELL=/bin/bash


%.yaml: %.json
	diff -w $< <(cfn-flip $< | cfn-flip)
	cfn-flip $< > $@
