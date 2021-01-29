/*
 *  params:
 *      auto: y to auto run the test
 *      users: number of users(windows to open)
 *      mode: ten/hundred/"", default is ""
 *      host: the hostname
 *      server: server address
 * example:
 *  https://localhost:8888/test.html?auto=y&server=localhost%3A5909&users=1&mode=ten&host=localhost%3A8888&close=force
 */
var gInternal = true;
var protocol = "https";
var protocolPort = 8443;

window.TestSuiteManager = (function(TestSuiteManager) {
    var windowRefs = [];
    var reports = [];
    var checkInterval;
    var curRunRefreshRate = 1000;
    var metaRefreshRate = 5000;

    var timeDilation = 1;

    TestSuiteManager.setup = function() {
        $(".run").click(function() {
            startRun();
        });

        $(".clear").click(function() {
            clearForm();
        });

        $(".closeAll").click(function() {
            closeAll();
        });

        $(".closeAll").hide();

        parseParam();
        if (gInternal) {
            populateParams();
            populatePreviousRuns();
            populateCurrentUsers();
        }
        startPoll();
    };

    TestSuiteManager.reportResults = function(id, results) {
        console.log(id, results);
        var res = "Fail: " +
            results.fail + ", Pass: " + results.pass + ", Skip: " +
            results.skip + ", Time: " + results.time + "s";
        if (results.error) {
            res += " , Error: " + results.error;
        }
        var status;
        $(".results .row").eq(id).find(".rightCol").html(res);
        printToServer(id + ":: " + res);
        if (results.fail > 0) {
            $(".results .row").eq(id).addClass("fail");
            status = "fail";
        } else {
            var cur = $(".overall").text();
            var nums = cur.split("/");
            $(".overall").text((parseInt(nums[0]) + 1) + "/" + nums[1]);
            $(".results .row").eq(id).addClass("pass");
            status = "pass";
        }

        reports[id] = "status:" + status + res;
    };

    TestSuiteManager.getAllWindowRefs = function() {
        return windowRefs;
    };

    TestSuiteManager.clearInterval = function() {
        clearInterval(checkInterval);
        checkInterval = undefined;
    };

    function parseParam() {
        var params = getSearchParameters();
        var numUsers = Number(params.users);
        if (isNaN(numUsers)) {
            numUsers = 5;
        } else {
            numUsers = Math.max(numUsers, 1);
        }

        var mode = params.mode;
        var hostname = parseHostName(params.host);
        var autoRun = params.auto;
        timeDilation = params.timeDilation;
        var close = params.close;

        $("#numUsers").val(numUsers);
        $("#mode").val(mode);

        if (hostname != null) {
            $("#hostname").val(hostname);
        }

        if (close === "y" || close === "force") {
            $("#close").val(close);
        }

        if (autoRun === "y") {
            startRun();
        }
    }

    function parseHostName(name) {
        if (!name) {
            return null;
        }

        name = decodeURIComponent(name);
        if (!name.startsWith(protocol)) {
            name = protocol + "://" + name;
        }
        if (protocol === "https" && !name.endsWith(":" + protocolPort)) {
            name =  name + ":" + protocolPort;
        }

        return name;
    }

    function startRun() {
        results = [];
        // Check arguments are valid. If not, populate with defaults
        var $inputs = $(".input");
        var numUsers = parseInt($inputs.eq(0).val());
        if (isNaN(numUsers)) {
            numUsers = 1;
            $inputs.eq(0).val(1);
        }
        var delay = parseInt($inputs.eq(1).val());
        if (isNaN(delay)) {
            delay = 0;
            $inputs.eq(1).val(0);
        }
        var animate = $inputs.eq(2).val();
        if (animate !== "y" && animate !== "n") {
            animate = "y";
            $inputs.eq(2).val("y");
        }
        var cleanup = $inputs.eq(3).val();
        if (cleanup !== "y" && cleanup !== "n" && cleanup !== "force") {
            cleanup = "y";
            $inputs.eq(3).val("y");
        }
        var close = $inputs.eq(4).val();
        if (close !== "y" && close !== "n" && close !== "force") {
            close = "y";
            $inputs.eq(4).val("y");
        }
        var hostname = $inputs.eq(5).val();
        if ($.trim(hostname).length === 0) {
            hostname = protocol + "://localhost:" + protocolPort;
            $inputs.eq(5).val(hostname);
        }

        var mode = $inputs.eq(6).val();
        if (mode !== "ten" && mode !== "hundred") {
            mode = "";
            $inputs.eq(6).val(mode);
        }

        // Disable the start button
        $(".run").addClass("inactive");
        $(".input").attr("disabled", true);
        $(".closeAll").show();
        $(".results").html("");

        // Start the run
        windowRefs = [];
        var i = 0;
        var curDelay = 0;
        for (i = 0; i < numUsers; i++) {
            var urlString = hostname + "/testSuite.html?type=testSuite&" +
                                        "test=y&noPopup=y";
            if (delay > 0) {
                urlString += "&delay=" + curDelay;
            }
            if (animate === "y") {
                urlString += "&animation=y";
            }
            if (cleanup !== "n") {
                urlString += "&cleanup=" + cleanup;
            }
            if (close !== "n") {
                urlString += "&close=" + close;
            }
            if (mode !== "") {
                urlString += "&mode=" + mode;
            }
            if (timeDilation != 1) {
                urlString += "&timeDilation=" + timeDilation;
            }
            // Generate a random username
            var username = "ts-" + Math.ceil(Math.random() * 1000000);
            urlString += "&user=" + username;
            urlString += "&id=" + i;
            var ref = window.open(urlString);
            windowRefs.push(ref);

            curDelay += delay;
            $(".results").append('<div class="row">' +
              '<div class="leftCol">Instance ' + i + '</div>' +
              '<div class="rightCol">Running...</div>' +
            '</div>');
        }
        $(".overall").html("0/" + numUsers);
        startCloseCheck(numUsers);
    }

    function clearForm() {
        $(".input").val("");
    }

    function closeAll() {
        TestSuiteManager.clearInterval();
        var i = 0;
        for (i = 0; i<windowRefs.length; i++) {
            windowRefs[i].close();
        }
        $(".input").attr("disabled", false);
        $(".run").removeClass("inactive");
    }

    function startCloseCheck(numUsers) {
        clearInterval(checkInterval);
        checkInterval = setInterval(function() {
            closeCheckReported(numUsers);
        }, 500);
    }

    function closeCheckReported(numUsers) {
        var id = 0;
        for (id = 0; id < numUsers; id++) {
            if (windowRefs[id].closed && $(".results .row").eq(id)
                               .find(".rightCol").text().indexOf("Run") === 0) {
                $(".results .row").eq(id).find(".rightCol")
                                  .text("Closed by user prior to completion");
                $(".results .row").eq(id).addClass("close");
                reports[id] = "status:close";
            }
        }
        var allDone = true;
        for (id = 0; id < numUsers; id++) {
            if (!$(".results .row").eq(id).hasClass("pass") &&
                !$(".results .row").eq(id).hasClass("fail") &&
                !$(".results .row").eq(id).hasClass("close")) {
                allDone = false;
            }
        }
        if (allDone) {
            TestSuiteManager.clearInterval();
            $(".input").attr("disabled", false);
            $(".run").removeClass("inactive");
            reportToServer();
        }
    }

    function reportToServer() {
        var params = getSearchParameters();
        var server = params.server;
        if (!server) {
            return;
        }
        server = decodeURIComponent(server);

        // http://host:port/action?name=setstatus&res=res
        var output = "";
        reports.forEach(function(res, index) {
            output += "user" + index + "?" + res + "&";
        });
        output = encodeURIComponent(output);

        var url = server + "/action?name=setstatus&res=" + output;
        if (gInternal) {
            $.ajax({
                "type"    : "GET",
                "dataType": "jsonp",  // this is to fix cross domain issue
                "url"     : url,
                "success" : function(data) {
                    console.log("send to sever success");
                },
                "error": function(error) {
                    console.log("send to sever error", error);
                }
            });
        }
    }

    function printToServer(res) {
        console.log(res);
        var params = getSearchParameters();
        var server = params.server;
        if (!server) {
            return;
        }
        server = decodeURIComponent(server);

        // http://host:port/action?name=print&res=res
        output = encodeURIComponent(res);

        var url = server + "/action?name=print&res=" + output;

        if (gInternal) {
            $.ajax({
                "type"    : "GET",
                "dataType": "jsonp",  // this is to fix cross domain issue
                "url"     : url,
                "success" : function(data) {
                    console.log("send to sever success");
                },
                "error": function(error) {
                    console.log("send to sever error", error);
                }
            });
        }
    }

    function getSearchParameters() {
        var prmstr = window.location.search.substr(1);
        return prmstr != null && prmstr !== "" ? transformToAssocArray(prmstr) : {};
    }

    function transformToAssocArray(prmstr) {
        var params = {};
        var prmarr = prmstr.split("&");
        for ( var i = 0; i < prmarr.length; i++) {
            var tmparr = prmarr[i].split("=");
            params[tmparr[0]] = tmparr[1];
        }
        return params;
    }

    function populatePreviousRuns() {
        // NOTE: This call MUST be idempotent. This call will be called every
        // x seconds and refreshed
        JenkinsTestData.getHistoricalRuns()
        .then(function(ret) {
            // Data is returned in descending order
            var html = "";
            for (var i = 0; i < ret.length; i++) {
                var extraClass = "";
                if (i === 0 && ret[i].totalUsers - ret[i].successUsers > 0) {
                    extraClass = "";
                } else if (ret[i].totalUsers - ret[i].successUsers > 0) {
                    extraClass = "fail";
                } else {
                    extraClass = "pass";
                }
                html += '<div class="row ' + extraClass + '">';
                html += '<div class="pastBuild">' + ret[i].build + '</div>';
                var val;
                if (!ret[i].start) {
                    val = "N/A";
                } else {
                    val = ret[i].start.split(".")[0];
                }
                html += '<div class="pastTime">' + val + '</div>';
                html += '<div class="pastDuration">' + ret[i].duration +
                        '</div>';
                html += '<div class="pastResults">' + ret[i].successUsers + "/" +
                        ret[i].totalUsers + '</div>';
                html += '</div>';
            }
            $("#pastRuns .results").html(html);
        });
    }

    function populateCurrentUsers() {
        // NOTE: This call MUST be idempotent. This call will be called every
        // x seconds and refreshed
        JenkinsTestData.getEachUserStatus()
        .then(function(ret) {
            var html = "";
            for (var i = 0; i < ret.length; i++) {
                var status = "";
                var text = "Not started";
                switch (ret[i].status) {
                    case ('Failed'):
                        status = "fail";
                        text = "Time: " + ret[i].duration + "s" + ret[i].error;
                        break;
                    case ('Success'):
                        status = "pass";
                        text = "Time: " + ret[i].duration + "s";
                        break;
                    default:
                        status = "";
                        text = "Running: " + ret[i].duration + "s";
                }
                html += '<div class="row ' + status + '">' +
                          '<div class="leftCol">User ' + i + '</div>' +
                          '<div class="rightCol">' + text +'</div>' +
                        '</div>';

            }
            $(".rightSection .results").html(html);
        });
    }

    function populateParams() {
        JenkinsTestData.getParamsForLastBuild()
        .then(function(ret) {
            var html = "";
            for (var i = 0; i < ret.length; i++) {
                html += '<div class="option">' +
                          '<input class="input" type="text" autocomplete="off" value="' + ret[i].value + '">' +
                          '<div class="bar">' + ret[i].name + '</div>' +
                        '</div>';
            }
            $(".leftSection .topSection").html(html);
        });
    }

    function startPoll() {
        setInterval(function() {
            populateParams();
            populatePreviousRuns();
        }, metaRefreshRate);
        setInterval(populateCurrentUsers, curRunRefreshRate);
    }

    return (TestSuiteManager);
}({}));

$(document).ready(function() {
    TestSuiteManager.setup();
});

function reportResults(id, results) {
    TestSuiteManager.reportResults(id, results);
}
