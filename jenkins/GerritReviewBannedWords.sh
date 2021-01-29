#!/bin/bash

FILES="$(git diff --name-only HEAD^ HEAD | egrep '\.(c|cpp|hpp|h)$')"
test -z "$FILES" && exit 0
git diff -w --diff-filter=AM HEAD^ HEAD -- $FILES | grep '^\+' | sed -e 's,//.*$,,g' > diff.txt
if egrep "$REGEX" diff.txt; then
   echo >&2 "Found a match, review carefully!"
   exit 0
fi
exit 0
