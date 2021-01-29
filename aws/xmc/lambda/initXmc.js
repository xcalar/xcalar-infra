var AWS = require('aws-sdk');
var cloudformation = new AWS.CloudFormation();
/**
 * Called once by cfn to copy API url to given bucket.
 * @param {*} event : make sure event.bucketName is passed,
 * @param {*} context 
 * @param {*} callback 
 */
exports.handler = (event, context, callback) => {
    var params = {};
    if (event.nextToken) {
        params["NextToken"] = event.nextToken
    }
   cloudformation.listExports(params, function(err, data) {
        if (err) {
            callback(err, err.stack); // an error occurred
        }
        else {
            var s3 = new AWS.S3();
            var params = {
                Bucket: data.bucketName,
                Key: "xmc/src/api.json",
                Body: JSON.stringify(data)
            }
            s3.putObject(params, function(err, data) {
                if (err) {
                    callback(err, err);
                }
                else {
                    callback(null, "SUCCESS");
                }
            });
        }
    });
};