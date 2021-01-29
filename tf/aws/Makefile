.PHONY: all validate plan graph apply

NAME := $(shell basename $(PWD))
TF_ARGS =
TF = terraform

all: validate plan

validate:
	$(TF) validate

graph: $(NAME).png

plan: $(NAME).plan

apply: $(NAME).plan
	$(TF) $(TF_ARGS) apply

$(NAME).plan: validate
	$(TF) $(TF_ARGS) plan -out=$@

$(NAME).dot:
	$(TF) $(TF_ARGS) graph > $@

$(NAME).png: $(NAME).dot
	dot -Tpng -o$@ < $<
