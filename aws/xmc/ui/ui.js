// This file contains cluster related functions such as functions to 
// Dynamically generate cluster grid or sorting clusters 
// For ui functions, raw data is passed and html elemenets returned

/*
function getColorClassForStatus:
returns color class name for cluster status
*/
function getColorClassForStatus(status) {
    switch (status) {
        case "Running":
            return "green-text";
            break;
        case "Provisioning Failed":
        case "Deleting":
        case "Delete Failed":
        case "Deleted":
        case "Stopped":
            return "red-text";
            break;
        case "Provisioning":
            return "orange-text";
            break;
    }
}

/*
function getIconClassForStatus:
returns icon class name for cluster status
*/
function getIconClassForStatus(status) {
    switch (status) {
        case "Running":
            return "green-light icon-xi-success";
            break;
        case "Provisioning Failed":
        case "Deleting":
        case "Delete Failed":
        case "Deleted":
        case "Stopped":
            return "red-light icon-xi-error";
            break;
        case "Provisioning":
            return "yellow-light icon-xi-error";
            break;
    }
}

let statusHash = {
    "CREATE_COMPLETE": "Running",
    "DELETING": "Deleting",
    "DELETE_FAILED": "Delete Failed",
    "CREATE_IN_PROGRESS": "Provisioning",
    "CREATE_FAILED": "Provisioning Failed",
    "DELETE_COMPLETE": "Deleted",
};

/*
function generateClusterRow
Generates html of one row in cluster list grid.
clusterData [] : array of strings. Cluster Name
Status
Nodes
Mode
Version
Xem
XD
            {
                fields : {
                    clusterName : "Xcalar-1",    // Name of the Xcalar cluster
                    "Status" : Running,         // Status string (Running, Stopped, Provisioning)
                    "Nodes" : 4,           // Number of nodes in cluster ,  
                    "Mode" : "Mixed" ,           // Xcalar Mode (Mixed, Modal, Open)
                    "Version" : "1.4.1",        // Xcalar Version
                    "XEM" : "N/A",            // N/A yet
                    "XD" : "192.168.2.1"             // Link to XD , it is usually IP of node0                    
                },
            }

    var clusterData1 = [
        "Test-Cluster-well1",
        "Running",
        2,
        "Mixed",
        "1.4.1",
        "N/A",
        "192.0.0.1"
    ];

*/
function uiGenerateClusterRow(data) {
    var templateHTML = "<div class=\"cluster-row\">" +
        "<div class=\"cluster-row-check cluster-column-one\">" +
        "<label class=\"container\"><input   data-cluster-name = \"" + data.fields["clusterName"] + "\" class =\"cluster-check\"  type=\"checkbox\"><span  class=\"checkmark\"></span></label>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-two\">" +
        "<div data-cluster-name = \"" + data.fields["clusterName"] + "\" class=\"cluster-row-cell-inner cluster-name\"> " +
        data.fields["clusterName"] +
        "</div>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-three\">" +
        "<div class=\"cluster-row-cell-inner " + getColorClassForStatus(data.fields["status"]) + "\"> " +
        data.fields["status"] +
        "</div>" +
        //        "<div data-cluster-status-text=\""+data.fields["statusReason"]+"\"class=\"cluster-row-cell-inner cluster-status-tip " + getIconClassForStatus(data.fields["status"]) + "\"></div>" +
        "<div data-hint=\"" + data.fields["statusReason"] + "\" class=\"cluster-hint-available cluster-row-cell-inner cluster-status-tip " + getIconClassForStatus(data.fields["status"]) + "\"></div>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-four\">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        data.fields["nodes"] +
        "</div>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-five\">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        data.fields["mode"] +
        "</div>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-six\">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        data.fields["version"] +
        "</div>" +
        "</div>" +
        "<div class=\"cluster-row-cell cluster-column-seven\">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        data.fields["xem"] +
        "</div>" +
        "</div>";

    if (data.fields["status"] == "Provisioning" || data.fields["status"] == "Running") {
        templateHTML +=
            "<div class=\"cluster-row-cell-no-space cluster-column-seven\">" +
            "<div class=\"cluster-row-cell-inner\"> " +
            "Open" +
            "</div>" +
            "<div class=\"cluster-row-cell-inner icon-xi-data-out clickable\"  onclick=\"gotoURL('" + data.fields["xd"] + "')\"    > " +
            "</div>" +
            "</div>"
    } else {
        templateHTML +=
            "<div class=\"cluster-row-cell-no-space cluster-column-seven\">" +
            "<div class=\"cluster-row-cell-inner\"> " +
            "--" +
            "</div>" +
            "</div>"
    }
    templateHTML += "<div class=\"cluster-row-cell cluster-column-rest\">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        "</div>" +
        "</div>";
    templateHTML += "</div>";
    return $(templateHTML);
}

function generateHeaderCell(field, label, extraClasses) {
    let htmlStr =
        "<div data-field-name=\"" + field + "\" class=\"header-clickable cluster-row-cell-header cluster-row-cell " + extraClasses + " \">" +
        "<div class=\"cluster-row-cell-inner\"> " +
        "<b>" + label + "</b>" +
        "</div>";
    if (clusterData.sortField == field && clusterData.sortDirecton == "asc") {
        htmlStr += "<div class=\"header-clickable cluster-row-cell-inner  sorted-asc icon-xi-arrow-up\"></div>";
    }
    if (clusterData.sortField == field && clusterData.sortDirecton == "dec") {
        htmlStr += "<div class=\"header-clickable cluster-row-cell-inner  sorted-des icon-xi-arrow-down\"></div>";
    }
    htmlStr += "</div>";
    return htmlStr;
}

function uiGenerateClusterHeader() {
    let templateHTML = "<div class=\"cluster-row\">" +
        "<div class=\"cluster-row-cell-header cluster-row-check cluster-column-one\">" +
        "<label class=\"container\"><input id=\"select-all-clusters\" type=\"checkbox\"><span class=\"checkmark select-all-clusters\"></span></label>" +
        "</div>";
    templateHTML += generateHeaderCell("clusterName", "Cluster Name", "cluster-column-two");
    templateHTML += generateHeaderCell("status", "Status", "cluster-column-three");
    templateHTML += generateHeaderCell("nodes", "Nodes", "cluster-column-four");
    templateHTML += generateHeaderCell("mode", "Mode", "cluster-column-five");
    templateHTML += generateHeaderCell("version", "Version", "cluster-column-six");
    templateHTML += generateHeaderCell("xem", "XEM", "cluster-column-seven");
    templateHTML += generateHeaderCell("xd", "XD", "cluster-column-seven");
    templateHTML += generateHeaderCell("other", "Other", "cluster-column-rest");
    templateHTML += "</div>"
    return $(templateHTML);
}

/*
    returns cluster details from clusterData (data.js)
*/
function getClusterDetails(clusterName) {
    for (var id = 0; id < clusterData.clusters.length; id++) {
        var cluster = clusterData.clusters[id];
        if (cluster.fields["clusterName"] == clusterName) {
            return cluster;
        }
    }
    return null;
}

/*
    Dynamically generated contents' event handlers should be repeatedly set after adding , removing new items
    This function re-set event handlers for cluster list. call it whenever cluster list is changed.
*/
function setClusterListEventHandlers() {
    $(".cluster-hint-available").hover(function() {
            var position = $(this).offset();
            console.log(position);
            position.left += 20;
            position.top += 20;
            $("#hintBox").show();
            $("#hintBox").offset(position);
            console.log("looking for hint");
            var hint = $(this).attr("data-hint"); //no hash 
            if (hint) {
                $("#hintBox").html(hint);
            }
        },
        function() {
            $("#hintBox").hide();
        }
    );
    $(".header-clickable").click(function(e) {
        console.log($(this).attr("data-field-name"));
        sortClusterList($(this).attr("data-field-name"))
    });
    $(".select-all-clusters").click(function(e) {
        sortClusterList(clusterData.sortField, clusterData.sortDirecton);
        clusterData.selectedAll = !clusterData.selectedAll;
        $(".cluster-check").attr("checked", clusterData.selectedAll);
        $("#select-all-clusters").attr("checked", clusterData.selectedAll);
    });
    $(".cluster-name").click(function(e) {
        $(".cluster-detail-item-list2").hide();
        $(".node-list-container").removeClass("cluster-detail-item-list");
        $(".node-list-container").addClass("cluster-detail-item");
        var cluster = getClusterDetails($(this).attr("data-cluster-name"));
        if (cluster) {
            $(".cluster-detail-dialog").show();
            $("#lock_background").show();
            $(".cluster-detail-status").removeClass("green-text orange-text red-text").addClass(getColorClassForStatus(cluster.fields["status"]));
            $(".cluster-detail-status-icon").removeClass("green-text orange-text red-text").addClass(getColorClassForStatus(cluster.fields["status"]));
            $(".cluster-detail-status").text(cluster.fields["status"]);
            $(".cluster-detail-uptime").text(cluster.fields["uptime"]);
            $(".cluster-detail-version").text(cluster.fields["version"]);
            $(".cluster-detail-url").text(cluster.fields["installerUrl"]);
            $(".cluster-detail-root").text(cluster.fields["xcalarRoot"]);
            $(".cluster-detail-nodes").text(cluster.fields["nodes"]);
            $(".node-list").empty();
            cluster.fields["Nodes"].forEach(function(node) {
                $("<div>" + node + "</div>").appendTo($(".node-list"));
            });
        }
    });
}

function sortClusterList(fieldName, direction) {
    clusterData.sortField = fieldName;
    if (!direction) {
        if (clusterData.sortDirecton == "asc") {
            clusterData.sortDirecton = "dec";
        } else {
            clusterData.sortDirecton = "asc"
        }
    }
    clusterData.clusters.sort(function(c1, c2) {
        if (clusterData.sortDirecton == "asc") {
            return (c1.fields[fieldName] > c2.fields[fieldName]);
        } else {
            return (c1.fields[fieldName] <= c2.fields[fieldName]);
        }
    });
    $("#cList").empty();
    uiGenerateClusterHeader().appendTo($("#cList"));
    clusterData.clusters.forEach(function(cluster) {
        uiGenerateClusterRow(cluster).appendTo($("#cList"));
    });
    setClusterListEventHandlers();
}

/*
  Function that parses cloudformation template , retrieve parameters and append them in ui with default values
**/
function generateSettings(data) {
    data["Metadata"]["AWS::CloudFormation::Interface"]["ParameterGroups"].forEach(function(pGroup) {
        var htmlStr = "<div class = \"settings-group-label\">" + pGroup.Label.default+"</div>";
        $(htmlStr).appendTo($(".installer-settings-content"));
        pGroup.Parameters.forEach(function(setting) {
            if (!ignoreList.includes(setting)) {
                var container = $("<div class = \"setting-container band\"></div>");
                container.appendTo($(".installer-settings-content"));
                $("<div data-hint-key =\"" + setting + "\" class=\"icon-xi-help setting-help-icon hint-available\"></div>").appendTo(container);
                $("<div class = \"setting-label\">" + setting + "</div>").appendTo(container);
                if (!data.Parameters[setting].AllowedValues) {
                    var elem = $("<input id=\"" + setting + "\" class= \"setting-text settingWidget\" type=\"text\">");
                    elem.val(data.Parameters[setting].Default);
                    elem.appendTo(container);
                } else {
                    var selectBoxContaier = $("<div></div>");
                    var items = [];
                    data.Parameters[setting].AllowedValues.forEach(function(item) {
                        items.push(item);
                    })
                    selectBoxContaier.appendTo(container);
                    var selectBox = new CustomSelect(selectBoxContaier, items, data.Parameters[setting].Default);
                }
            }
        })
        var container = $("<div class = \"setting-spacer-div\"></div>");
        container.appendTo($(".installer-settings-content"));
    })
}