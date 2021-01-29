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
import pprint
import shutil
import sys

if __name__ == '__main__':
    sys.path.append(os.environ.get('XLRINFRADIR', ''))

from coverage.clang import ClangCoverageDir
from py_common.env_configuration import EnvConfiguration

cur_dir = os.path.dirname(os.path.realpath(__file__))

# XXXrs - ad hoc :(
XCE_CRITICAL_FILES = ["liboperators/GlobalOperators.cpp",
                      "liboperators/LocalOperators.cpp",
                      "liboperators/XcalarEval.cpp",
                      "liboptimizer/Optimizer.cpp",
                      "libxdb/Xdb.cpp",
                      "libruntime/Runtime.cpp",
                      "libquerymanager/QueryManager.cpp",
                      "libqueryeval/QueryEvaluate.cpp",
                      "libmsg/TwoPcFuncDefs.cpp",
                      "totals"]

def _header_row():
    return {'items':[{'class':'column-entry-left', 'text': 'Filename'},
                     {'class':'column-entry', 'text': 'Function Coverage'},
                     {'class':'column-entry', 'text': 'Instantiation Coverage'},
                     {'class':'column-entry', 'text': 'Line Coverage'},
                     {'class':'column-entry', 'text': 'Region Coverage'}]}

def _data_row(*, vals):
    # XXXrs - ad hoc :(
    items = []
    for val in vals:
        if not items:
            # Filename
            fields = val.split('/')
            if len(fields) < 2:
                filename = val
            else:
                filename = "{}/{}".format(fields[-2], fields[-1])
            if filename == 'totals':
                filename = 'TOTALS'
            items.append({'class':'column-entry-left', 'text': filename}) 
        else:
            # Percentage data
            flt_val = float(val)
            color = 'green'
            if flt_val < 1.0:
                color = 'red'
            elif flt_val < 5.0:
                color = 'yellow'
            fmt_val = "{:.2f}%".format(flt_val)
            items.append({'class':'column-entry-{}'.format(color), 'text': fmt_val}) 
    return {'class': 'light-row', 'items': items}

def _table(*, rows):
    # Start
    tbl_str = "<table>\n"

    # Rows
    for row in rows:
        cls = row.get('class', None)
        if cls:
            tbl_str += "<tr class=\'{}\'>\n".format(cls)
        else:
            tbl_str += "<tr>\n"

        for item in row['items']:
            cls = item.get('class', None)
            if cls:
                tbl_str += "<td class={}>{}</td>\n".format(cls, item['text'])
            else:
                tbl_str += "<td>{}</td>\n".format(item['text'])

        tbl_str += "</tr>\n"

    # End
    tbl_str += "</table>\n"
    return tbl_str

if __name__ == '__main__':

    cfg = EnvConfiguration({"LOG_LEVEL": {"default": logging.INFO}})
    logging.basicConfig(level=cfg.get("LOG_LEVEL"),
                        format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                        handlers=[logging.StreamHandler()])
    logger = logging.getLogger(__name__)

    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="base directory", required=True)
    parser.add_argument("--new", help="directory to compare against base", required=True)
    # XXXrs - ad hoc :(
    parser.add_argument("--xce_critical", help="only show XCE \"critical\" files", action="store_true")
    parser.add_argument("--out", help="output directory", default=cur_dir)
    args = parser.parse_args()

    if args.out:
        if not os.path.exists(args.out):
            raise ValueError("output path {} does not exist".format(args.out))
        if not os.path.isdir(args.out):
            raise ValueError("output path {} is not a directory".format(args.out))

    base = ClangCoverageDir(coverage_dir=args.base)
    new = ClangCoverageDir(coverage_dir=args.new)
    diff_rslt = new.diff(base_dir=base)


    # Start HTML output...

    html_str = "<html>\n"
    html_str += "<head>\n"
    html_str += "<meta name='viewport' content='width=device-width,initial-scale=1'>\n"
    html_str += "<meta charset='UTF-8'><link rel='stylesheet' type='text/css' href='style.css'>\n"
    html_str += "</head>\n"
    html_str += "<body>\n"

    html_str += "<h2>Coverage Difference Report</h2>\n"
    html_str += "<h4>{} -> {}</h4>\n".format(args.base, args.new)
    if args.xce_critical:
        html_str += "<p><b>Critical XCE Files Only</b></p><br/>\n"
    else:
        html_str += "<p><b>All Files</b></p><br/>\n"


    only_base = diff_rslt.get('only_base', None)
    if only_base:
        # XXXrs - IMPLEMENT TABLE HERE?
        logger.warning("only_base: {}".format(pprint.pformat(only_base)))

    only_new = diff_rslt.get('only_new', None)
    if only_new:
        # XXXrs - IMPLEMENT TABLE HERE?
        logger.warning("only_new: {}".format(pprint.pformat(only_new)))

    rows = [_header_row()]

    diffs = diff_rslt.get('diffs', {})
    for key in sorted(diffs.keys()):
        if args.xce_critical:
            for cfile in XCE_CRITICAL_FILES:
                if cfile in key:
                    break
            else:
                continue
        '''
        Keyed diff values like:

        {'lines': {'count': 2527, 'covered': 395, 'percent': 15.631183221210922},
         'functions': {'count': 27, 'covered': 2, 'percent': 7.407407407407407},
         'instantiations': {'count': 27, 'covered': 2, 'percent': 7.407407407407407},
         'regions': {'count': 931, 'covered': 149, 'percent': 16.004296455424274}}
        '''
        diff_vals = diffs[key]
        rows.append(_data_row(vals=[key, diff_vals['functions']['percent'],
                                         diff_vals['instantiations']['percent'],
                                         diff_vals['lines']['percent'],
                                         diff_vals['regions']['percent']]))

    html_str += _table(rows=rows)

    # End HTML output...
    html_str += "</head>\n"
    html_str += "</html>\n"

    dst_css = os.path.join(args.out, 'style.css')
    if not os.path.exists(dst_css):
        logger.debug("{} doesn't exist")
        our_css = os.path.join(cur_dir, 'style.css')
        shutil.copyfile(our_css, dst_css)
    else:
        logger.debug("{} already exists, will not overwrite".format(dst_css))

    dst_html = os.path.join(args.out, 'index.html')
    with open(dst_html, 'w+') as fd:
        fd.write(html_str)
