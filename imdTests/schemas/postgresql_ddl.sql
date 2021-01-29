-- DROP DATABASE IF EXISTS ecommercedb;

-- CREATE DATABASE ecommercedb  WITH OWNER = postgres;

-- GRANT ALL ON DATABASE ecommercedb TO jenkins;

--Create tables

-- Table: public.customer
DROP TABLE IF EXISTS public.customers CASCADE;

CREATE TABLE public.customers
(
  customerid integer NOT NULL,
  title varchar(10),
  firstname varchar(100),
  lastname varchar(100),
  job varchar(100),
  email varchar(100),
  modifieddate date,
  cust_1 varchar(100),
  cust_2 varchar(100),
  cust_3 varchar(100),
  cust_4 varchar(100),
  cust_5 varchar(100),
  cust_6 varchar(100),
  cust_7 varchar(100),
  cust_8 varchar(100),
  cust_9 varchar(100),
  opcode integer,
  CONSTRAINT customer_pkey PRIMARY KEY (customerid)
);

ALTER TABLE public.customers
  OWNER TO jenkins;

-- Table: public.customer_phone
DROP TABLE IF EXISTS public.customer_phone CASCADE;

CREATE TABLE public.customer_phone
(
  phonenum varchar(30) NOT NULL,
  customerid integer REFERENCES customers,
  phonetype varchar(20),
  modifieddate date,
  cust_phone_1 varchar(100),
  cust_phone_2 varchar(100),
  cust_phone_3 varchar(100),
  cust_phone_4 varchar(100),
  cust_phone_5 varchar(100),
  cust_phone_6 varchar(100),
  cust_phone_7 varchar(100),
  cust_phone_8 varchar(100),
  cust_phone_9 varchar(100),
  cust_phone_10 varchar(100),
  opcode integer,
  CONSTRAINT phone_pkey PRIMARY KEY (phonenum)
);

ALTER TABLE public.customer_phone
  OWNER TO jenkins;

-- Table: public.address
DROP TABLE IF EXISTS public.address CASCADE;

CREATE TABLE public.address
(
  addressid varchar(50) NOT NULL,
  apt varchar(20),
  street varchar(100),
  city varchar(100),
  state varchar(20),
  zipcode varchar(50),
  modifieddate date,
  address_1 varchar(100),
  address_2 varchar(100),
  address_3 varchar(100),
  address_4 varchar(100),
  address_5 varchar(100),
  address_6 varchar(100),
  opcode integer,
  CONSTRAINT address_pkey PRIMARY KEY (addressid)
);

ALTER TABLE public.address
  OWNER TO jenkins;

-- Table: public.customer_address
DROP TABLE IF EXISTS public.customer_address CASCADE;

CREATE TABLE public.customer_address
(
  addressid varchar(50) REFERENCES address,
  customerid integer REFERENCES customers,
  addresstype varchar(20),
  modifieddate date,
  opcode integer,
  PRIMARY KEY (addressid, customerid)
);

ALTER TABLE public.customer_address
  OWNER TO jenkins;

-------------------------------------------------------------------------------

-- Table: public.product_category, like mens, womens kids
DROP TABLE IF EXISTS public.product_category CASCADE;

CREATE TABLE public.product_category
(
  productcategoryid integer PRIMARY KEY,
  name varchar(20),
  modifieddate date
);

ALTER TABLE public.product_category
  OWNER TO jenkins;

-- Table: public.product_sub_category
DROP TABLE IF EXISTS public.product_sub_category CASCADE;

CREATE TABLE public.product_sub_category
(
  productsubcategoryid integer PRIMARY KEY,
  productcategoryid integer REFERENCES product_category,
  name varchar(20),
  modifieddate date
);

ALTER TABLE public.product_sub_category
  OWNER TO jenkins;

-- Table: public.product
DROP TABLE IF EXISTS public.product CASCADE;

CREATE TABLE public.product
(
  productid integer PRIMARY KEY,
  productsubcategoryid integer REFERENCES product_sub_category,
  name varchar(20),
  color varchar(10),
  listprice numeric,
  size varchar(5),
  weight numeric,
  avgrating numeric,
  modifieddate date
);

ALTER TABLE public.product
  OWNER TO jenkins;

-------------------------------------------------------------------------------
DROP TABLE IF EXISTS public.orders CASCADE;

CREATE TABLE orders (
    orderid integer PRIMARY KEY,
    customerid integer REFERENCES customers,
    addressid varchar(50) REFERENCES address(addressid),
    orderdate date,
    status varchar(20),
    modifieddate date,
    order_1 varchar(100),
    order_2 varchar(100),
    order_3 varchar(100),
    order_4 varchar(100),
    order_5 varchar(100),
    order_6 varchar(100),
    order_7 varchar(100),
    order_8 varchar(100),
    order_9 varchar(100),
    opcode integer
);

ALTER TABLE public.orders
  OWNER TO jenkins;

DROP TABLE IF EXISTS public.order_items CASCADE;

CREATE TABLE order_items (
    orderitemsid varchar(50) NOT NULL,
    orderid integer REFERENCES orders,
    productid integer,
    quantity integer,
    unitprice numeric,
    modifieddate date,
    order_item_1 varchar(100),
    order_item_2 varchar(100),
    order_item_3 varchar(100),
    order_item_4 varchar(100),
    order_item_5 varchar(100),
    order_item_6 varchar(100),
    order_item_7 varchar(100),
    order_item_8 varchar(100),
    order_item_9 varchar(100),
    order_item_10 varchar(100),
    order_item_11 varchar(100),
    order_item_12 varchar(100),
    opcode integer,
    PRIMARY KEY (orderitemsid, orderid)
);

ALTER TABLE public.order_items
  OWNER TO jenkins;
