#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import logging
import os
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from py_common.jenkins_aggregators import JenkinsAggregatorBase

# The AGGREGATOR_PLUGINS list registers aggregator plug-in classes with Jenkins jobs.
# Each entry in the list is a dictionary of the form:
#
#   {'class': <class name>, 'job_names': [<jenkins job name>, ...]}
#
#

AGGREGATOR_PLUGINS = [{'class_name': 'ExampleAggregator', 
                       'job_names': ['BuildTrunk']}]

# Aggregator class must subclass from JenkinsAggregatorBase

class ExampleAggregator(JenkinsAggregatorBase):
    def __init__(self, *, job_name):
        """
        Class-specific initialization.
        """
        # MUST call superclass initializer.
        super().__init__(job_name=job_name, agg_name=self.__class__.__name__)
        self.logger = logging.getLogger(__name__)


    def update_build(self, *, jbi, log, is_reparse=False, test_mode=False):
        """
        Aggregate and return build-related data and meta-data.
        Every aggregator must implement the update_build() method.
        See JenkinsAggregatorBase for details.
        """
        self.logger.info("Hello from ExampleAggregator!")
        self.logger.info("jbi: {}".format(jbi))
        self.logger.info("log: {}".format(log))
        self.logger.info("is_reparse: {}".format(is_reparse))
        self.logger.info("test_mode: {}".format(test_mode))
        return None

# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")
