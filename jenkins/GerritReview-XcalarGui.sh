#!/bin/bash

export XLRGUIDIR=`pwd`

if [ "$(git diff --diff-filter=AM HEAD^ -- assets/js/constructor/D* | wc -l)" -gt 0 ]; then echo >&2 "You cannot change past constructors!"; exit 1; fi

exit 0
