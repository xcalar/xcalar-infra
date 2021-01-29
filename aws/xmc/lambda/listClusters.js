/*
    Lambda function that lists the clusters
    1-Scan DynamoDB and get cluster list  construct clster list json
    2-describe clusters with cloudformation API get status information and ec2 instance IPs
    3-Add status and instances to the list
*/
var regionName = process.env.AWS_REGION;
var AWS = require('aws-sdk');
var cloudformation = new AWS.CloudFormation();
var docClient = new AWS.DynamoDB.DocumentClient();
var tableName = "XMC_TABLE_NAME";
var ec2 = new AWS.EC2({
    region: regionName
});

/*
 * function to retrieve cluster list from database
 * Description of this ordinary function in the Drupal namespace goes here.
 * @param
 *   none
 * @return
 *   a promise that resolves with cluster array
 *      fails with error object
 */
function scanClusters() {
    var params = {
        TableName: tableName
    };
    var dynamoScan = new Promise(function(resolve, reject) {
        var results = [];
        var onScan = (err, data) => {
            if (err) {
                return reject(err);
            }
            results = results.concat(data.Items);
            if (typeof data.LastEvaluatedKey != 'undefined') {
                params.ExclusiveStartKey = data.LastEvaluatedKey;
                docClient.scan(params, onScan);
            } else {
                return resolve(results);
            }
        };
        docClient.scan(params, onScan);
    });
    return dynamoScan;
}
/**
 * resolves a given promise with stack information (cluster)
 * @param {Function} resolve :promise resolve callback
 * @param {Function} reject :promise reject function
 * @param {Array} stackNames : array of stack names to describe
 * @param {unsigned int``} currentID  : function is used recursively , helper integer to point current stack name
 * @param {Array of cluster info objects} results  : what is being returned , an array of cluster info
 */
function describeStack(resolve, reject, stackNames, currentID, results) {
    if (!results) {
        results = [];
    }

    var params = {
        "StackName": stackNames[currentID]
    };
    //call cloudformation api to get stack data
    cloudformation.describeStacks(params, function(err, data) {
        if (!err) {
            results.push(data);
        }
        if (currentID < (stackNames.length - 1)) {
            currentID++;
            describeStack(resolve, reject, stackNames, currentID, results)
        } else {
            resolve(results);
        }
    });
}

function getParameterValue(Items, paramKey) {
    var rv;
    Items.Parameters.forEach(function(param) {
        if (param.ParameterKey === paramKey) {
            rv = param.ParameterValue;
            return;
        }
    });
    return rv;
}
/**
 * returns the EC2 instance data of given cluster (Nodes of the cluster)
 */

function instances(stackName) {
    var pGetNodes = new Promise(function(resolve, reject) {
        var params = {
            Filters: [{
                Name: "tag:aws:cloudformation:stack-name",
                Values: [stackName]
            }]
        };
        ec2.describeInstances(params, function(err, data) {
            if (err) {
                reject("failed");
            } // an error occurred
            else {
                var returnValue = {
                    clusterName: stackName
                };
                returnValue["instanceIPS"] = [];
                for (var id = 0; id < data.Reservations.length; id++) {
                    var n = data.Reservations[id];
                    for (var id2 = 0; id2 < n.Instances.length; id2++) {
                        var instance = n.Instances[id2];

                        if (instance["PublicIpAddress"]) {
                            returnValue["publicIP"] = instance["PublicIpAddress"].toString();
                            returnValue["nodeCount"] = n.Instances.length;
                            returnValue["instanceIPS"].push(instance["PublicIpAddress"].toString());
                        }
                    }
                }
                resolve(returnValue);
            }
        });
    });
    return pGetNodes;
}

//Cfn has 20 status for stacks , we hash them to 4-5
let statusHash = {
    "CREATE_COMPLETE": "Running",
    "ROLLBACK_COMPLETE": "Failed",
    "DELETING": "Deleting",
    "DELETE_FAILED": "Delete Failed",
    "CREATE_IN_PROGRESS": "Provisioning",
    "CREATE_FAILED": "Provisioning Failed",
    "ROLLBACK_IN_PROGRESS": "Provisioning Failed",
    "ROLLBACK_FAILED": "Provisioning Failed",
    "ROLLBACK_COMPLETE": "Provisioning Failed",
    "DELETE_IN_PROGRESS": "Deleting",
    "DELETE_FAILED": "Delete Failed",
    "DELETE_COMPLETE": "Deleted",
    "UPDATE_IN_PROGRESS": " Provisioning",
    "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS": "Provisioning",
    "UPDATE_COMPLETE": "Running",
    "UPDATE_ROLLBACK_IN_PROGRESS": "Provisioning Failed",
    "UPDATE_ROLLBACK_FAILED": "Delete Failed",
    "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS": "Provisioning Failed",
    "UPDATE_ROLLBACK_COMPLETE": "Deleted",
    "REVIEW_IN_PROGRESS": "Provisioning"
};

exports.handler = (event, context, callback) => {
    let clustersHash = {}; //cluster name : cluster Data
    scanClusters().then(function(clustersFromDB) {
            clustersFromDB.forEach(function(cData) {
                if (cData.ID != "settings") {
                    var clusterData = {
                        fields: {
                            "clusterName": cData.ID,
                            "status": "Deleted", // Status string (Running, Stopped, Provisioning)
                            "nodes": getParameterValue(cData.cfnParams, "InstanceCount"), // Number of nodes in cluster ,  
                            "mode": "N/A", // Xcalar Mode (Mixed, Modal, Open)
                            "version": "1.4.1", // Xcalar Version
                            "xem": "N/A", // N/A yet
                            "xd": "N/A", // Link to XD , it is usually IP of node0                    
                            "other": "", // Reserved                    
                            "uptime": 0, //uptime in seconds
                            'Nodes': [],
                            "InstallerUrl": "N/A",
                            "XcalarRoot": "N/A"
                        }
                    };
                    clustersHash[cData.ID] = clusterData;
                }
            });
            //So far so good
            var clusterNames = [];
            for (var key in clustersHash) {
                clusterNames.push(key);
            }
            var promise = new Promise(function(resolve, reject) {
                describeStack(resolve, reject, clusterNames, 0);
            });
            promise.then(function(results) {
                    var promise = new Promise(function(resolve, reject) {
                        var clusterCount = results.length;
                        if (results.length == 0) {
                            resolve(clustersHash);
                            return;
                        } else {
                            results.forEach(function(elem) {
                                elem.Stacks.forEach(function(stack) {
                                    if (clustersHash[stack.StackName]) {
                                        clustersHash[stack.StackName]["fields"]["status"] = statusHash[stack.StackStatus];
                                        clustersHash[stack.StackName]["fields"]["statusReason"] = stack.StackStatusReason;
                                        instances(stack.StackName)
                                        .then(function(instanceObj) {
                                            instanceObj["instanceIPS"].forEach(function(IP) {
                                                clustersHash[instanceObj["clusterName"]]["fields"]["Nodes"].push(IP);
                                                clustersHash[instanceObj["clusterName"]]["fields"]["xd"] = IP;
                                            })
                                            clusterCount--;
                                            if (clusterCount == 0) {
                                                resolve(clustersHash);
                                            }
                                        })
                                        .catch(function(err) {
                                            clusterCount--;
                                            if (clusterCount == 0) {
                                                resolve(clustersHash);
                                            }
                                        });
                                    }
                                });
                            });
                        }
                    });
                    promise.then(function(clustersHash) {
                            //convert cluster hash to an array for ui consume
                            var returnData = {
                                sortField: "clusterName",
                                sortDirecton: "dec",
                                selectedAll: false,
                                clusters: []
                            };
                            for (var key in clustersHash) {
                                returnData.clusters.push(clustersHash[key]);
                            }
                            callback(null, returnData);
                        })
                        .catch(function(err) {
                            callback(null, clustersHash);
                        })
                })
                .catch(function(err) {
                    callback(null, clustersHash);
                })
        })
        .catch(function(err) {
            callback(err, "FAILED");
        })
};