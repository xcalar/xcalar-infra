var path = require("path");

exports.creds = {

    // Required. Identity of the AWS User Pool that defines the user(s)
    userPoolId: 'YOUR_USER_POOL_ID',

    // Required. Id of the client AWS application which requires authentication
    clientId: 'YOUR_CLIENT_ID',

    // Optional. URL where keys for JWT verification can be found.  Uses AWS default if null.
    keysUrl: null,

    // Required. Region where authentication is occurring -- location of User Pool and Identity Pool.
    region: 'YOUR_AWS_REGION',

    // Optional. Id of the Identity Pool required for authentication.
    identityPoolId: 'YOUR_IDENTITY_POOL_ID',

    // Optional. The amount of logging that the strategy does.
    loggingLevel: 'warn',

    // Required to set to true if the `verify` function has 'req' as the first parameter
    passReqToCallback: false
};

exports.useDynamoDBSessionStore = true;

exports.dynamoDBSessionStoreTable = 'YOUR_DYNAMODB_SESSION_TABLE_NAME';

exports.dynamoDBSessionStoreHashKey = 'id';

exports.dynamoDBSessionStorePrefix = 'xc';

exports.sessionAges = {
    interactive: 1800000,
    api: 7200000,
    sql: 7200000,
    test: 30000
};

exports.defaultSessionAge = 'interactive';

exports.dynamoDBUserTable = 'YOUR_DYNAMODB_USER_TABLE_NAME';

exports.dynamoDBCredsTable = 'YOUR_DYNAMODB_CREDS_TABLE_NAME';

exports.sessionSecret = 'keyboard cat';
