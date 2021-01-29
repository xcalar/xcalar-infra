#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

AGGREGATOR_PLUGINS = [{'module_path': 'coverage.xce_func_test_coverage',
                       'class_name': 'XCEFuncTestCoverageAggregator',
                       'job_names': ['XCEFuncTest']},

                      {'module_path': 'coverage.xd_unit_test_coverage',
                       'class_name': 'XDUnitTestCoverageAggregator',
                       'job_names': ['XDUnitTest']}]

# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")
