#!/usr/bin/env node
'use strict'

const modifyFiles = require('./utils').modifyFiles
const packageJson = require('../package.json')
const config = packageJson.config

modifyFiles(['./simple-proxy-api.yaml', './package.json', './cloudformation.yaml', './config.js'], [{
  regexp: new RegExp(config.accountId, 'g'),
  replacement: 'YOUR_ACCOUNT_ID'
}, {
  regexp: new RegExp(config.s3BucketName, 'g'),
  replacement: 'YOUR_UNIQUE_BUCKET_NAME'
}, {
  regexp: new RegExp(config.functionName, 'g'),
  replacement: 'YOUR_SERVERLESS_EXPRESS_LAMBDA_FUNCTION_NAME'
}, {
  regexp: new RegExp(config.sessionTableName, 'g'),
  replacement: 'YOUR_DYNAMODB_SESSION_TABLE_NAME'
}, {
  regexp: new RegExp(config.userTableName, 'g'),
  replacement: 'YOUR_DYNAMODB_USER_TABLE_NAME'
}, {
  regexp: new RegExp(config.credsTableName, 'g'),
  replacement: 'YOUR_DYNAMODB_CREDS_TABLE_NAME'
}, {
  regexp: new RegExp(config.identityPoolId, 'g'),
  replacement: 'YOUR_IDENTITY_POOL_ID'
}, {
  regexp: new RegExp(config.userPoolId, 'g'),
  replacement: 'YOUR_USER_POOL_ID'
}, {
  regexp: new RegExp(config.clientId, 'g'),
  replacement: 'YOUR_CLIENT_ID'
}, {
  regexp: new RegExp(config.region, 'g'),
  replacement: 'YOUR_AWS_REGION'
}, {
  regexp: new RegExp(config.corsOrigin, 'g'),
  replacement: 'YOUR_CORS_ORIGIN'
}, {
  regexp: new RegExp(config.cloudFormationStackName, 'g'),
  replacement: 'AwsServerlessExpressStack'
}])
