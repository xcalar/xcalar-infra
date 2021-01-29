#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import argparse
import logging
import os
import sys

if __name__ == '__main__':
    logger = logging.getLogger(__name__)
    xlrinfra = os.environ.get('XLRINFRADIR', '')
    logger.debug("XLRINFRADIR: {}".format(xlrinfra))
    sys.path.append(xlrinfra)

from coverage.clang import ClangCoverageDir
from py_common.env_configuration import EnvConfiguration

if __name__ == '__main__':

    cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.INFO}})
    logging.basicConfig(level=cfg.get("LOG_LEVEL"),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)


    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", help="coverage directory to process",
                        dest='coverage_dirs', action='append', required=True)
    parser.add_argument("--out", help="output directory to store merged results",
                        required=True)
    parser.add_argument("--src", help="directory containing sources to use for llvm-cov show",
                        required=True)
    parser.add_argument("--force", help="force re-creation of all files", action='store_true')
    args = parser.parse_args()

    ClangCoverageDir.merge(dirs=args.coverage_dirs, out_dir=args.out, src_dir=args.src, force=args.force)
