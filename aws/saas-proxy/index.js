var express = require('express');
var app = express();
var cors = require('cors');
var httpProxy = require('http-proxy');
var AWS = require('aws-sdk');
var tcpp = require('tcp-ping');

var ec2 = new AWS.EC2({region: "us-west-2"});
var dynamodb = new AWS.DynamoDB({region: "us-west-2"});
var proxy = httpProxy.createServer();
var ipCache = {};

app.use(cors());
app.all("*", async function (req, res) {
    // xcalar cluster forwarding
    var username;
    for (var key in req.headers) {
        if (key.toLowerCase() === "username") {
            username = req.headers[key];
        }
    }
    if (ipCache[username]) {
        // cached
        var ip = ipCache[username];
        var target = 'https://' + ip;
        tcpp.ping({address: ip, port: 443, attempts: 1, timeout: 500}, function(err, data) {
            if (data.min !== undefined) {
                console.log("hitting cache");
                proxy.web(req, res, {target: target, secure: false});
            } else {
                // if cache is stale
                console.log("updating cache");
                proxyRequest(username, req, res);
            }
        });
    } else {
        proxyRequest(username, req, res);
    }
}).listen(9000);

async function proxyRequest(username, req, res) {
    // not hitting cache
    var ip;
    var target;
    try {
        ip = await getIpFromUsername(username);
        target = 'https://' + ip;
    } catch(e) {
        console.log(e, e.stack);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({error: "Failed to get address of cluster"}));
        return;
    }
    proxy.web(req, res, {target: target, secure: false});
    ipCache[username] = ip;
}

async function getIpFromUsername(username) {
    var params = {
        Filters: [
            {
                "Name": "tag:Owner",
                "Values": [username]
            }
        ]
    };
    var data = await ec2.describeInstances(params).promise();
    var reservations = data.Reservations;
    var allInstances = [];
    for (var reservation of data.Reservations) {
        for (var instance of reservation.Instances) {
            if (instance.State.Name === "running") {
                allInstances.push({
                    index: instance.AmiLaunchIndex,
                    timestamp: instance.LaunchTime,
                    ip: instance.PrivateIpAddress
                });
            }
        }
    }
    if (allInstances.length < 1) {
        // no instance
        throw "No running cluster";
    }
    allInstances.sort(function(i1, i2) {
        if (i1.timestamp === i2.timestamp) {
            return i1.index - i2.index;
        } else {
            return i1.timestamp - i2.timestamp;
        }
    });
    var ip = allInstances[0].ip;
    return ip;
}

// server.on('connect', function (req, socket) {
//     var ip;
//     if (routingMap.hasOwnProperty(req.headers.username)) {
//         ip = routingMap[req.headers.username];
//     } else {
//         var params = {
//             Key: {
//                 "username": {
//                     S: req.headers.username
//                 }
//             }, 
//             TableName: "saas_routing"
//         };
//         try {
//             let resp = await dynamodb.getItem(params);
//             ip = resp.Item.Address.S;
//         } catch (e) {
//             console.error("failed: ", e);
//         }
//     }
//     var target = 'http://' + ip + '6578';
//     proxy.ws(req, socket, {target: target, secure: false});
// });

