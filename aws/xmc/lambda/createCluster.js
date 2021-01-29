/**
 * Lambda that initiates the creation of a cluster with cloudformation
 * required post data is cloudformation params in jason
 * minimum req is instanceCount and name of the cluster , defaults are used for non provided params
 * Flow of the function
 * 1. Check if cluster is in the database
 * 2. If it is, ignore passed params and use the params from DB (Starting a previously stopped cluster)
 * 3. If it is not in the db , post it to DB
 * 4. Initiate stack that creates cluster
 */

var AWS = require('aws-sdk');
var cloudformation = new AWS.CloudFormation();
var docClient = new AWS.DynamoDB.DocumentClient(); //dynamodb object to get cluster data

/**
 * provision a cluster for cluster name and cfn params
 * returns a promise that resolves if:
 *  cfn stack is legal and creation started
 * that rejects if:
 * cfn doesnt accep the template:
 * cfn templates' being accepted by AWS doesnt guarantee the provisioning of clusters
 * can roll back , fail for millions of reasons , stack status' should be watched closely
 * 
 */
function provisionCluster(clusterName, cfnTemplate) {
  let templateContent = "";
  let fs = require('fs');
  //load the cached cfn template
  var pDB = new Promise(function(resolve, reject) {
    fs.readFile('cfn_template', function(err, data) { //<<== FIX ME , change it to a url
      if (err) {
        reject("Can not open template file");
        return;
      }
      templateContent = data.toString();
      cfnTemplate.TemplateBody = templateContent;
      cloudformation.createStack(cfnTemplate, function(err, data) {
        if (err) { //API fails
          reject(JSON.stringify(err));
        } // an error occurred
        else { //API successfull
          resolve(data);
        }
      });

    });
  });
  return pDB;
}

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
      "ID": event.StackName,
    }
  };
  //Promise below resolves if cluster params are posted , fails if something goes wrong with db
  var pDB = new Promise(function(resolve, reject) {
    docClient.get(params, function(err, data) {
      if (err) {
        reject(JSON.stringify(err, null, 2))
      } else {
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

// Entry point of lambda , event  argument is the post data coming from client application
exports.handler = (event, context, callback) => {
  var tableName = "XMC_TABLE_NAME";
  var clusterName = event.stackName;
  var action = event.action;
  var cfnTemplate = event.cfnTemplate;
  var provisionPromise = new Promise(function(resolve, reject) {
    if (action == "start") {
      //check if cluster is in DB
      getClusterData(clusterName, tableName)
      .then(function(item) {
        //we have cfn params for the cluster , if the action is start , we use the existing params
        if (JSON.stringify(item) === '{}') //something is wrong , trying to re-provision a cluster doesnt exist in db
        {
          reject("UI ERROR.");
        } else //we found a stopped (deleted) cluster , just provision it with existing params
        {
          //start provissioning with existing data
          provisionCluster(clusterName, item.cfnParams).
          then(function() {
            cfnTemplate = item.cfnParams;
            resolve();
          }).
          catch(function(err) {
            reject(err);

          })
        }
      })
      .catch(function() {
        reject("", "DB ERROR.");
      });
    }
    if (action == "create") {
      provisionCluster(clusterName, cfnTemplate)
        .then(function() {
          resolve();
        }).
      catch(function(err) {
        reject(err);
      })
    }
  });
  provisionPromise
    .then(function() { //at this point cfn accpeted our params and started the provisioning
      //put cluster data back
      setClusterData(clusterName, tableName, cfnTemplate, action)
        .then(function() {
          callback(null, "SUCCESS");
        })
        .catch(function(err) {
          callback(err, err);
        });
    })
    .catch(function(err) {
      callback(err, err);
    });
};