#!/usr/bin/env python3

# Copyright 2019 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import os

class EnvConfigurationMissingRequired(Exception):
    pass

class EnvConfigurationInvalidType(Exception):
    pass

class EnvConfigurationInvalidValue(Exception):
    pass

class EnvConfiguration(object):
    """
    Extract configuration from environment according to the
    parameter requirements passed to the initializer.

    {"key" : {"type" : <STRING | NUMBER | BOOLEAN>,
              "default" : <value>,
              "required" : "true"/"false" }}
    """
    STRING = "STRING"
    NUMBER = "NUMBER"
    BOOLEAN = "BOOLEAN"

    def __init__(self, params):

        self.cfg = {}
        for key, info in params.items():
            default = info.get(key, info.get('default', None))

            val = os.environ.get(key, default)

            if info.get('required', False) and val is None:
                raise EnvConfigurationMissingRequired(
                        "Missing required parameter {}".format(key))


            ptype = info.get('type', EnvConfiguration.STRING)

            if ptype == EnvConfiguration.STRING:
                self.cfg[key] = val
                continue

            if ptype == EnvConfiguration.BOOLEAN:
                if val.lower() == 'true':
                    self.cfg[key] = True
                    continue
                elif val.lower() == 'false':
                    self.cfg[key] = False
                    continue
                else:
                    raise EnvConfigurationInvalidValue(
                            "Invalid value \"{}\" for boolean parameter {}"
                            .format(val, key))

            if ptype != EnvConfiguration.NUMBER:
                raise EnvConfigurationInvalidType(
                        "Invalid type \"{}\" for parameter {}"
                        .format(ptype, key))

            # Must be a NUMBER, try to convert.
            try:
                self.cfg[key] = int(val)
            except ValueError as e:
                try:
                    self.cfg[key] = float(val)
                except Exception:
                    raise EnvConfigurationInvalidValue(
                            "Invalid value \"{}\" for number parameter {}"
                            .format(val, key)) from None

    def get(self, key, default=None):
        return self.cfg.get(key, default)

# In-line "unit test"
if __name__ == '__main__':
    print("Compile check A-OK!")

    test_params = {
            'SOME_STR': {'type': EnvConfiguration.STRING,
                         'required': True},
            'SOME_NUM': {'type': EnvConfiguration.NUMBER,
                         'required': True},
            'SOME_BOOL': {'type': EnvConfiguration.BOOLEAN,
                          'required': True},
            'XYZZY': {'default': 'xyzzy'}
            }

    saw_exception = False
    try:
        cfg = EnvConfiguration(test_params)
    except EnvConfigurationMissingRequired:
        saw_exception = True

    if not saw_exception:
        raise Exception("Missing parameter exception not seen")

    os.environ['SOME_STR'] = "A test string"
    os.environ['SOME_NUM'] = "123"
    os.environ['SOME_BOOL'] = "true"

    cfg = EnvConfiguration(test_params)

    os.environ['SOME_NUM'] = "foo"

    saw_exception = False
    try:
        cfg = EnvConfiguration(test_params)
    except EnvConfigurationInvalidValue:
        saw_exception = True
    if not saw_exception:
        raise Exception("Failed to detect bad number type")

    os.environ['SOME_NUM'] = "123"

    for not_ok in ['foo', 'Tru', 'F']:
        os.environ['SOME_BOOL'] = not_ok
        saw_exception = False
        try:
            cfg = EnvConfiguration(test_params)
        except EnvConfigurationInvalidValue:
            saw_exception = True
        if not saw_exception:
            raise Exception("Failed to detect bad boolean type {}"
                            .format(not_ok))

    for ok in ['true', 'True', 'TrUe', 'false', 'False', 'FALSE']:
        os.environ['SOME_BOOL'] = ok
        cfg = EnvConfiguration(test_params)

    assert(cfg.get('XYZZY') == 'xyzzy')
    print("Success!")
