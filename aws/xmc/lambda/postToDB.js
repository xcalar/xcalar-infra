/**
 * lambda that posts cluster configs to dynamoDB
 */
exports.handler = (event, context, callback) => {
    var regionName = process.env.AWS_REGION;
    if (JSON.stringify(event).length > 10000) //simple byte check to avoid  flood attacks
    {
        callback(null, "Bad Data");
    }
    var AWS = require("aws-sdk");
    AWS.config.update({
        region: regionName
    });
    var docClient = new AWS.DynamoDB.DocumentClient();
    var table = "XMC_TABLE_NAME"; // table name is replaced during build
    var params = {
        TableName: table,
        Item: event
    };
    docClient.put(params, function (err, data) {
        if (err) {
            callback(err, JSON.stringify(err, null, 2));
        } else {
            callback(null, ["OK"]);
        }
    });
};