#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

AGGREGATOR_PLUGINS = [{'module_path': 'sql_perf',
                       'class_name': 'SSTResultsAggregator',
                       'job_names': ['SqlScaleTest']},
                      {'module_path': 'sql_perf',
                       'class_name': 'BSTAResultsAggregator',
                       'job_names': ['BuildSqldfTestAggreagate']}]

# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")
