import pytest
from discover import schema_checksum

@pytest.fixture()
def columns():
    return {
       "columns1" : [ { "Name": "A", "Mapping": "$.A", "SqlType": "VARCHAR(8)" }, { "Name": "C", "Mapping": "$.C", "SqlType": "VARCHAR(8)" }, { "Name": "B", "Mapping": "$.B", "SqlType": "INTEGER" } ],
       "columns2" : [ { "Name": "A", "Mapping": "$.A", "SqlType": "VARCHAR(8)" }, { "Name": "B", "Mapping": "$.B", "SqlType": "INTEGER" }, { "Name": "C", "Mapping": "$.C", "SqlType": "VARCHAR(8)" } ],
       "columns3" : [ { "Name": "A", "Mapping": "$.A", "SqlType": "VARCHAR(8)" }, { "Name": "C", "Mapping": "$.C", "SqlType": "VARCHAR(8)" }, { "Name": "B", "Mapping": "$.B", "SqlType": "INTEGER" } ],
       "columns4" : [ { "Name": "F", "Mapping": "$.F", "SqlType": "VARCHAR(8)" }, { "Name": "C", "Mapping": "$.C", "SqlType": "VARCHAR(8)" }, { "Name": "B", "Mapping": "$.B", "SqlType": "INTEGER" } ]
    }

def test_schema_parity(columns):
    checksum = schema_checksum.SchemaChecksum()
    checksum1 = checksum.compute_checksum(columns["columns1"], strict_order=False)
    checksum2 = checksum.compute_checksum(columns["columns2"], strict_order=False)
    assert checksum1 == checksum2
    checksum1 = checksum.compute_checksum(columns["columns1"])
    checksum2 = checksum.compute_checksum(columns["columns2"])
    assert checksum1 != checksum2
    checksum1 = checksum.compute_checksum(columns["columns1"])
    checksum2 = checksum.compute_checksum(columns["columns3"])
    assert checksum1 == checksum2
    checksum1 = checksum.compute_checksum(columns["columns1"])
    checksum2 = checksum.compute_checksum(columns["columns4"])
    assert checksum1 != checksum2
    checksum1 = checksum.compute_checksum(columns["columns1"], strict_order=False)
    checksum2 = checksum.compute_checksum(columns["columns4"], strict_order=False)
    assert checksum1 != checksum2
