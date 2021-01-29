#!/usr/bin/env node
'use strict'

const fs = require('fs')
const exec = require('child_process').execSync
const modifyFiles = require('./utils').modifyFiles

let minimistHasBeenInstalled = false

if (!fs.existsSync('./node_modules/minimist')) {
  exec('npm install minimist --silent')
  minimistHasBeenInstalled = true
}

const args = require('minimist')(process.argv.slice(2), {
  string: [
    'account-id',
    'bucket-name',
    'function-name',
    'region',
    'user-table-name',
    'session-table-name',
    'creds-table-name',
    'identity-pool-id',
    'user-pool-id',
    'client-id',
    'cloudformation-stack',
    'cors-origin'
  ],
  default: {
    region: 'us-east-1',
    'function-name': 'AwsServerlessExpressFunction'
  }
})

if (minimistHasBeenInstalled) {
  exec('npm uninstall minimist --silent')
}

const accountId = args['account-id']
const bucketName = args['bucket-name']
const functionName = args['function-name']
const userTableName = args['user-table-name']
const sessionTableName = args['session-table-name']
const credsTableName = args['creds-table-name']
const userPoolId = args['user-pool-id']
const identityPoolId = args['identity-pool-id']
const clientId = args['client-id']
const corsOrigin = args['cors-origin']
const cloudFormationStackName = args['cloudformation-stack'] ?
      args['cloudformation-stack'] : 'AwsServerlessExpressStack'

const region = args.region

if (!accountId || accountId.length !== 12) {
  console.error('You must supply a 12 digit account id as --account-id="<accountId>"')
  process.exit(1)
}

if (!bucketName) {
  console.error('You must supply a bucket name as --bucket-name="<bucketName>"')
  process.exit(1)
}

if (!userTableName) {
  console.error('You must supply a user table name as --user-table-name="<userTableName>"')
  process.exit(1)
}

if (!sessionTableName) {
  console.error('You must supply a session table name as --sesson-table-name="<sessionTableName>"')
  process.exit(1)
}

if (!credsTableName) {
  console.error('You must supply a creds table name as --creds-table-name="<credsTableName>"')
  process.exit(1)
}

if (!identityPoolId) {
  console.error('You must supply an identity pool id as --identity-pool-id="<identityPoolId>"')
  process.exit(1)
}

if (!userPoolId) {
  console.error('You must supply a user pool id as --user-pool-id="<userPoolId>"')
  process.exit(1)
}

if (!clientId) {
  console.error('You must supply a client id as --client-id="<clientId>"')
  process.exit(1)
}

if (!corsOrigin) {
    console.error('You must supply a CORS origin as --cors-origin="<origin URL>"')
}

modifyFiles(['./simple-proxy-api.yaml', './package.json', './cloudformation.yaml', './config.js'], [{
  regexp: /YOUR_ACCOUNT_ID/g,
  replacement: accountId
}, {
  regexp: /YOUR_AWS_REGION/g,
  replacement: region
}, {
  regexp: /YOUR_UNIQUE_BUCKET_NAME/g,
  replacement: bucketName
}, {
  regexp: /YOUR_SERVERLESS_EXPRESS_LAMBDA_FUNCTION_NAME/g,
  replacement: functionName
}, {
  regexp: /YOUR_DYNAMODB_SESSION_TABLE_NAME/g,
  replacement: sessionTableName
}, {
  regexp: /YOUR_DYNAMODB_USER_TABLE_NAME/g,
  replacement: userTableName
}, {
  regexp: /YOUR_DYNAMODB_CREDS_TABLE_NAME/g,
  replacement: credsTableName
}, {
  regexp: /YOUR_IDENTITY_POOL_ID/g,
  replacement: identityPoolId
}, {
  regexp: /YOUR_USER_POOL_ID/g,
  replacement: userPoolId
}, {
  regexp: /YOUR_CLIENT_ID/g,
  replacement: clientId
}, {
  regexp: /YOUR_CORS_ORIGIN/g,
  replacement: corsOrigin
}, {
  regexp: /AwsServerlessExpressStack/g,
  replacement: cloudFormationStackName
}])
