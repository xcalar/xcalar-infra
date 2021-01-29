var regionName = process.env.AWS_REGION;
var AWS = require('aws-sdk');
var cloudformation = new AWS.CloudFormation();
var docClient = new AWS.DynamoDB.DocumentClient();
AWS.config.update({ region: regionName });

/**
 * get cluster data from db
 * returns a promise that resolves if:
 * cluster data exists (resolves with cluster data)
 * cluster data doesnt exist (with empty object)
 * rejects of there is a db error thrown by dynamoapi
 * caller should check if if returned data is an empty object to test if cluster exists in db
 */
function getClusterData(clusterName, tableName) {

    var table = tableName; //table name is changed during build
    var params = {
        TableName: table,
        Key: {
            "ID": clusterName,
        }
    };
    //Promise below resolves if cluster params are posted , fails if something goes wrong with db
    var pDB = new Promise(function(resolve, reject) {

        docClient.get(params, function(err, data) {
            if (err) {

                reject(JSON.stringify(err, null, 2));
            }
            else {
                resolve(data);
            }
        });
    });
    return pDB;
}

/*
  returns a promise that resolves after upserting cluster data.
*/
function setClusterData(clusterName, tableName, cfnParams, lastAction) {
    var item = {
        ID: clusterName,
        cfnParams: cfnParams,
        lastAction: lastAction
    };
    var params = {
        TableName: tableName,
        Item: item
    };
    var pDB = new Promise(function(resolve, reject) {
        docClient.put(params, function(err, data) {
            if (err) {
                reject(JSON.stringify(err, null, 2));
            } else { //now since cluster is new , create the stack
                resolve();
            }
        });
    });
    return pDB;
}

/*
* Starts termination of a cluster
excepts a post json in following format
{
    name:clusterToBeDeleted (stack Name)
    action : [delete/stop]
}
clusterName: unique name of the cluster being terminated or stopped
*/
exports.handler = (event, context, callback) => {
    var params = {
        StackName: event.name  /* required */
    };
    let returnValue = {
        'statusCode': 502,
        'headers': { 'Content-Type': 'application/json' },
        'body': ""
    };
    var pDB = new Promise(function(resolve, reject) {
        getClusterData(event.name, "XMC_TABLE_NAME")
        .then(function(data) {
            resolve(data);
        }).
        catch(function(err) {
            reject(err);
        });
    });
    pDB
    .then(function(Item) {
        cloudformation.deleteStack(params, function(err, data) {
            if (err) {
                returnValue.statusCode = 502;
                returnValue.body = JSON.stringify(err);
                callback(null, returnValue);
            }
            else {
                returnValue.statusCode = 200;
                returnValue.body = JSON.stringify(data);
                //update db, change clusters last action
                console.log(Item);
                setClusterData(event.name, "XMC_TABLE_NAME", Item.cfnTemplate, "delete")

                callback(null, returnValue);
            }
        });
    })
    .catch(function(err) { // falls here if db operation fails
        callback(err, err);
    });
};
