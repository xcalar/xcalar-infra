import re
import json
import functools
import hashlib

# Kinesis JSON Schema
"""
"RecordColumns": [
    {
        "Name": "A",
        "Mapping": "$.A",
        "SqlType": "VARCHAR(8)"
    },
    {
        "Name": "B",
        "Mapping": "$.B",
        "SqlType": "INTEGER"
    },
    {
        "Name": "C",
        "Mapping": "$.C",
        "SqlType": "VARCHAR(8)"
    }
]
"""
class SchemaChecksum:
    def __init__(self):
        pass

    def colcmp(self, col1, col2):
        return 1 if col1["Name"] > col2["Name"] else -1

    # for eg. convert VARCHAR(16) to VARCHAR
    def normalize_schema(self, record_columns):
        record_columns = json.dumps(record_columns)
        return re.sub(r'\(\d*\)','', record_columns).encode('utf-8')

    def sort_columns(self, record_columns):
        return sorted(record_columns, key=functools.cmp_to_key(self.colcmp))

    def compute_checksum(self, record_columns, strict_order=True):
        if not strict_order:
            sorted_columns = self.sort_columns(record_columns)
        else:
            sorted_columns = record_columns
        normalized_columns = self.normalize_schema(sorted_columns)
        return hashlib.md5(normalized_columns).hexdigest()
