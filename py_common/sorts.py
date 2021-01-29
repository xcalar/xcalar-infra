#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import re

def nat_sort(s, nsre=re.compile('([0-9]+)')):
    return [int(t) if t.isdigit() else t.lower() for t in nsre.split(s)]
