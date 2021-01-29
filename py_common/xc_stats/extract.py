#!/usr/bin/env python3

# Copyright 2020 Xcalar, Inc. All rights reserved.
#
# No use, or distribution, of this source code is permitted in any form or
# means without a valid, written license agreement with Xcalar, Inc.
# Please refer to the included "COPYING" file for terms and conditions
# regarding the use and redistribution of this software.

import jmespath

"""
An "xy_expr" expression returns alternating x and y values when iterating over matches...

    json_data = {"foo":[{"xval":<x1>, "yval":<y1>},{"xval":<x2>, "yval":<y2>}]} 
    xy_expr = "$.foo.[xval,yval]"

An "key_expr/val_expr" expression pair uses the key expression to find a dictionary for which the
key values are one half of ... and the val_expr is used to find the paired values by matching
the structures "keyed" by each of the key values.

    json_data = {"foo": {<x1>:{"yval": <y1>, "bar": "something"},
                         <x2>:{"yval": <y2>, "bar": "something else"}}}
    key_expr = "$.foo"
    val_expr = "$.yval"

Both would result in:
        [(<x1>, <y1>), (<x2>, <y2>)]
"""
class JSONExtract(object):

    def __init__(self):
        self._compiled = {'keys(@)': jmespath.compile('keys(@)')}

    def compiled(self, *, expr):
        if expr not in self._compiled:
            self._compiled[expr] = jmespath.compile(expr)
        return self._compiled[expr]

    def extract_xy(self, *, xy_expr, dikt):
        expr = self.compiled(expr=xy_expr)
        return expr.search(dikt)

    def extract_kv(self, *, key_expr, val_expr, dikt):
        '''
        key_expr: identifies a document the keys of which become the
                  first element in each returned pair

        val_expr: for each key found in the document identified by key_expr,
                  use the key to identify a sub document, or list of sub documents
                  and val_expr to extract the value(s) to be returned as the second
                  element in each returned pair(s)
        '''
        vals = []

        kexpr = self.compiled(expr=key_expr)
        vexpr = self.compiled(expr=val_expr)
        keysfunc = self.compiled(expr='keys(@)')

        keys_doc = kexpr.search(dikt)
        keys = keysfunc.search(keys_doc)
        for key in keys:
            sub = keys_doc[key]
            if isinstance(sub, list):
                for dikt_item in sub:
                    val = vexpr.search(dikt_item)
                    vals.append([key, val])
            else:
                val = vexpr.search(sub)
                vals.append([key, val])
        return vals

if __name__ == "__main__":
    test_data={
        'foo': {'1234':{'sys': 4, 'idle': 96},
                '1235':{'sys': 5, 'idle': 95}},
        'bar': {'bongo': {'4567':{'sys': 40, 'idle': 60},
                          '4568':[{'sys': 50, 'idle': 50},
                                  {'sys': 51, 'idle': 49}]}},
        'blah': [{'x': 1, 'y': 10},
                 {'x': 2, 'y': 20},
                 {'x': 3, 'y': 30}]
        }

    je = JSONExtract()
    print("expect [[1, 10], [2, 20], [3, 30]]")
    print("got: {}".format(je.extract_xy(xy_expr="blah[*][x,y]", dikt=test_data)))

    print("expect [[1234, 4], [1235, 5]]")
    print("got: {}".format(je.extract_kv(key_expr="foo", val_expr="sys", dikt=test_data)))

    print("expect [[4567, 60], [4568, 50], [4568, 49]]")
    print("got: {}".format(je.extract_kv(key_expr="bar.bongo", val_expr="idle", dikt=test_data)))

    print("expect: {'x': 2, 'y': 20}")
    print("got: {}".format(jmespath.search("blah[?x==`2`]", test_data)))
