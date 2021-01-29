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

from py_common.env_configuration import EnvConfiguration
config = EnvConfiguration({'LOG_LEVEL': {'default': logging.DEBUG}})

from flask import Flask, request
from flask import render_template, make_response
from flask_cors import CORS, cross_origin

# It's log, it's log... :)
logging.basicConfig(
                level=config.get('LOG_LEVEL'),
                format="'%(asctime)s - %(threadName)s - %(funcName)s - %(levelname)s - %(message)s",
                handlers=[logging.StreamHandler()])
logger = logging.getLogger(__name__)

app = Flask(__name__)
cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'

methods=['GET']
@app.route('/', methods=methods)
@cross_origin()
def test_connection():
    """
    / should return 200 ok.
    """
    return "Connection check A-OK!"

# Template expects passed parameter
@app.route('/hello', methods=methods)
@app.route('/hello/<name>', methods=methods)
@cross_origin()
def hello(name=None):
    return render_template("hello.html", name=name)

# Template accesses the request object
@app.route('/hello_qs', methods=methods)
@cross_origin()
def hello_qs():
    return render_template("hello_qs.html")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4001, debug=True)
