import json
import os
import gzip
from xcalar.container.target import s3environ

def main(inStr):
    inObj = json.loads(inStr)
    contents = inObj["fileContents"]
    filePath = inObj["filePath"]
    chunks = filePath.lstrip("/").split("/")
    bucket = chunks[0]
    dirPath = "/".join(chunks[1:])
    s3 = s3environ.get_target("s3DatagenImport", None, None).connector.client
    compressedData = gzip.compress(bytearray(contents, "utf-8"))
    dirPath += ".gz"
    s3.put_object(Body=compressedData, Bucket=bucket, Key=dirPath)
