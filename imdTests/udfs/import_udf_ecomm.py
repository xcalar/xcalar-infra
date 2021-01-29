import json
import string
import sys
import random
import datetime
from faker import Faker
from faker.providers import BaseProvider
import time

maxNum = 1000000000
maxProdId = 5950

class CustomFaker(BaseProvider):
    def gender(self):
        genders = ['M', 'F']
        return random.choice(genders)

    def phonetype(self):
        phoneTypes = ["home", "office", "personal", "mobile", "cell"]
        return random.choice(phoneTypes)

    def random_string(self, str_len=6):
        return ''.join([random.choice(string.ascii_letters) for _ in range(str_len)])

    def datetime_now(self):
        return str(datetime.datetime.now())

    def product(self):
        return random.randint(1, maxProdId)

def __genCustPhone(fake):
    phoneTypes = ["home", "office", "personal", "mobile", "cell"]
    phoneDict = {}
    phoneDict["phonenum"] = fake.phone_number()
    phoneDict["phonetype"] = random.choice(phoneTypes)
    randCols = __genRandomCols(fake, "cust_phone", numCols = 10)
    phoneDict = {**phoneDict, **randCols}
    return phoneDict

def __genCustAddr(fake, custId):
    addrTypes = ["home", "office", "mailing"]
    randAddrId = random.randint(1, 20000)
    addrsId = "{}_{}".format(custId, randAddrId)
    addrDict = {}
    addr = fake.address().split()
    addrDict["addressid"] = addrsId
    addrDict["apt"] = fake.secondary_address()
    addrDict["street"] = fake.street_name()
    if len(addr) > 2:
        addrDict["city"] = addr[-3]
        addrDict["state"] = addr[-2]
        addrDict["zipcode"] = addr[-1]
    else:
        addrDict["city"] = fake.city()
        addrDict["state"] = fake.state()
        addrDict["zipcode"] = fake.zipcode()
    addrDict["addresstype"] = random.choice(addrTypes)
    randCols = __genRandomCols(fake, "address", numCols = 6)
    addrDict = {**addrDict, **randCols}
    return addrDict

def __genCustomer(fake):
    custId = random.randint(1, maxNum)
    cust = {}
    cust["customerid"] = custId
    cust["title"] = fake.suffix()
    cust["firstname"] = fake.first_name()
    cust["lastname"] = fake.last_name()
    cust["job"] = fake.job()
    cust["email"] = fake.free_email()
    randCols = __genRandomCols(fake, "cust", numCols = 9)
    addr = __genCustAddr(fake, custId)
    phone = __genCustPhone(fake)
    cust = {**cust, **phone, **addr, **randCols}
    return cust

def __genRandomCols(fake, prefix, numCols=9):
    formats = ['word',
        'domain_name',
        'color_name',
        'currency_code'
    ]
    randCols = {}
    for idx in range(1, numCols+1):
        col = "{}_{}".format(prefix, idx)
        format = formats[(idx-1)%len(formats)]
        randCols[col] = getattr(fake, format)()
    return randCols

def __genOrder(fake):
    order = {}
    order["orderid"] = random.randint(1, maxNum)
    order["status"] = random.choice(["placed", "shipped", "delivered"])
    order["orderdate"] = fake.datetime_now()
    randCols = __genRandomCols(fake, "order", numCols = 9)
    order = {**order, **randCols}
    return order

def __genOrderItems(fake, orderId):
    orderItems = []
    for idx in range(random.randint(5, 150)):
        orderItem = {}
        orderItem['orderitemsid'] = "{}_{}".format(orderId, idx+1)
        orderItem['productid'] = fake.product()
        orderItem['quantity'] = random.randint(2, 10)
        orderItem["unitprice"] = random.uniform(10, 500)
        randCols = __genRandomCols(fake, "order_item", numCols = 12)
        orderItem = {**orderItem, **randCols}
        orderItems.append(orderItem)
    return orderItems

def genData(filepath, instream, imd=False):
    inObj = json.loads(instream.read())
    if inObj["numRows"] == 0:
        return
    start = inObj["startRow"] + 1
    end = start + inObj["numRows"]

    fake = Faker()
    fake.seed(int(time.time()) + start)
    fake.add_provider(CustomFaker)
    random.seed(int(time.time()) + start)

    modDate = fake.datetime_now()
    while start < end:
        cust = __genCustomer(fake)
        order = __genOrder(fake)
        for orderItem in __genOrderItems(fake, order["orderid"]):
            res = {**cust, **order, **orderItem}
            res['opcode'] = 2 if imd else 1
            res['modifieddate'] = modDate
            yield res
            start += 1
