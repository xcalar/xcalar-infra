/**
 * lambda that gets config json of the XMC
 * return value is the config data ,posted previously
 */
exports.handler = (event, context, callback) => {
    if (JSON.stringify(event).length > 10000) //simple byte check to avoid  flood attacks
    {
        callback(null, "Bad Data");
    }
    var AWS = require("aws-sdk");
    var regionName = process.env.AWS_REGION;
    AWS.config.update({
        region: regionName 
    });
    var docClient = new AWS.DynamoDB.DocumentClient();
    var table = "XMC_TABLE_NAME";
    var params = {
        TableName: table,
        Key: {
            "ID": event.ID,
        }
    };
    docClient.get(params, function(err, data) {
        if (err) {
            callback(err, JSON.stringify(err, null, 2));
        } else {
            callback(null, data);
        }
    });
};