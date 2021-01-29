#!/bin/bash
ssh -oPort=29418 gerrit.int.xcalar.com -- gerrit "$@"
