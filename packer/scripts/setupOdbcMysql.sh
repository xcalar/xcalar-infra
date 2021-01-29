#!/bin/bash

databaseName="odbcTest"
tableName="Persons"

sudo service mysql start || true

mysql -uroot -e "help" 2>&1 | grep -q "Access denied"
requiresPassword=$?
if [ "$requiresPassword" = "1" ]; then
    password=""
else
    echo -n "Enter password: "
    read -s password
    echo
fi

if [ "$requiresPassword" = "1" ]; then
    mysql -uroot -e "show databases" | grep -q $databaseName
else
    mysql -uroot -p"$password" -e "show databases" | grep -q $databaseName
fi
ret=$?

if [ $ret != "0" ]; then
    echo "Database '$databaseName' does not exist in the local MySql"
    exit 1
fi

echo "$databaseName exists"

if [ "$requiresPassword" = "1" ]; then
    mysql -uroot -e "use $databaseName; show tables" | grep -q $tableName
else
    mysql -uroot -p"$password" -e "use $databaseName; show tables" | grep -q $tableName
fi
ret=$?

if [ $ret != "0" ]; then
    echo "Creating $tableName"
    read -r -d '' sqlQuery<<EOF
    use $databaseName
    CREATE TABLE $tableName
    (
    PersonID int,
    Name varchar(255),
    Employed bool,
    Height float
    );
EOF
    echo "$sqlQuery"
    if [ "$requiresPassword" = "0" ]; then
        echo "$sqlQuery" | mysql -uroot -p"$password"
    else
        echo "$sqlQuery" | mysql -uroot
    fi
fi

if [ "$requiresPassword" = "1" ]; then
    numRows=$(mysql -uroot -e \
        "use $databaseName; SELECT COUNT(*) FROM $tableName" | \
        cat | \
        grep -oE '[0-9]*')
else
    numRows=$(mysql -uroot -p"$password" -e \
        "use $databaseName; SELECT COUNT(*) FROM $tableName" | \
        cat | \
        grep -oE '[0-9]*')

fi

if [ "$numRows" != "2" ]; then
    echo "Inserting rows into $tableName"
    read -r -d '' sqlQuery<<EOF
    use $databaseName
    INSERT INTO $tableName
    (
    PersonID,
    Name,
    Employed,
    Height
    )
    VALUES
    (
    1,
    'John',
    false,
    6.5
    );

    INSERT INTO $tableName
    (
    PersonID,
    Name,
    Employed,
    Height
    )
    VALUES(
    2,
    'Betty',
    true,
    5.25
    );
EOF
    echo "$sqlQuery"
    if [ "$requiresPassword" = "0" ]; then
        echo "$sqlQuery" | mysql -uroot -p"$password"
    else
        echo "$sqlQuery" | mysql -uroot
    fi

else
    echo "Records already exist"

fi

