import psycopg2
import json

def _config_params():
    params = {}
    params["dbname"] = '<DBNAME>'
    params["user"] = '<DBUSER>'
    params["host"] = '<DBHOST>'
    params["port"] = '<DBPORT>'
    params["password"] = '<DBPASS>'
    return params

keyInfo = {'address': ['addressid'],
           'customer_address': ['addressid', 'customerid'],
           'customer_phone': ['phonenum'],
           'customers': ['customerid'],
           'order_items': ['orderitemsid', 'orderid'],
           'orders': ['orderid']
           }

def _prepareStatement(tableName, headers):
    keys = keyInfo[tableName]
    colStr = ["%({})s".format(colName) for colName in headers]

    remColNames = []
    remColValues = []
    for col in headers:
        if col in keys:
            continue
        remColNames.append(col)
        remColValues.append("EXCLUDED." + col)
    return '''INSERT INTO {} ({}) VALUES ({}) ON CONFLICT ({}) DO UPDATE SET ({}) = ({})
        '''.format(tableName, ', '.join(headers),
                   ', '.join(colStr), ', '.join(keys),
                   ', '.join(remColNames), ', '.join(remColValues))

def main(inStr):
    inObj = json.loads(inStr)
    rows = inObj["fileContents"]
    filePath = inObj["filePath"]
    chunks = filePath.lstrip("/").split("/")
    tableName = chunks[-2]
    try:
        params = _config_params()
        conn = psycopg2.connect(**params)
        cur = conn.cursor()
        headers = []
        listVals = []
        for row in rows.split('\n'):
            if not headers:
                for col in row.split('\t'):
                    headers.append(col)
                continue
            if not row.strip():
                continue
            vals = {}
            for idx, col in enumerate(row.split('\t')):
                vals[headers[idx]] = col
            if vals:
                listVals.append(vals)
        sqlStatement = _prepareStatement(tableName, headers)
        cur.executemany(sqlStatement, listVals)
        conn.commit()
        cur.close()
    except (Exception, psycopg2.DatabaseError) as error:
        ##debug statements
        # with open("/tmp/testDbExport.txt", 'w+') as f:
        #     f.write(tableName + '\n')
        #     f.write(str(listVals) + "\n")
        #     f.write(str(error) + "\n")
        #     f.write(sqlStatement + "\n")
        raise error
    finally:
        if conn:
            conn.commit()
            conn.close()
