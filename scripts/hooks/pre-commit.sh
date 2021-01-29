#!/bin/bash
DIRS=(azure aws scripts)
syntax_errors=0
against=4b825dc642cb6eb9a060e54bf8d69288fbee4904 # Empty tree
git rev-parse --quiet --verify HEAD >/dev/null && against=HEAD
CHANGES="$(git diff-index --diff-filter=AM --name-only --cached $against -- $DIRS | tr '\n' ' ')"
if [ -n "${CHANGES}" ]; then
	make --silent check D="${CHANGES}"
	if [ "$?" -ne 0 ]
	then
	    syntax_errors=$(($syntax_errors + 1))
	fi
fi

# Whitespace check
git diff-index --check --cached $against -- $DIRS || syntax_errors=$(($syntax_errors + 1))

# Any other checks you want

[ $syntax_errors -ne 0 ] && exit 1
exit 0
