#!/usr/bin/env python

from jinja2 import Environment, FileSystemLoader
import sys

try:
    errorMsg = sys.argv[1]
except:
    errorMsg = "Error message not specified"

try:
    rectifyMsg = sys.argv[2]
except:
    rectifyMsg = "Rectify message not specified"

env = Environment(loader=FileSystemLoader('templates/'))
template = env.get_template('error.html')

with open("index.html", "w") as fp:
    fp.write(template.render(XCALAR_ERROR_MSG=errorMsg, XCALAR_RECTIFY_MSG=rectifyMsg))





