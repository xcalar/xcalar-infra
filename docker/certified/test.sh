#!/bin/bash

echo foo

(cd /tmp && make)
rc=$?
echo rc=$rc
exit $rc
