function xmc() {
  let apiRootUrl = ""
  let suffix = "Xcalar";
  let activeNodeCount = 0;
  let UNIT_TESTING = true;

  /*gets the lambda API Url from autogenerated json file by ui deployment stack
   */
  $.getJSON("api.json", function(json) {
    apiRootUrl = json.Exports[0]["Value"];
    loadClusterList();
    loadPage(".settingWidget");
  });

  /*
  AJAX gate
  hide / show loading gif
  call the user function on received data
  @url : url to call
  @func : function to run on success
  @postData : Data to post to url
  */
  function ajaxCall(url, func, postData) {
    $("#ajax_loading").show();
    var ajaxOptions = {
      contentType: "application/json; charset=utf-8",
      dataType: "json",
      url: url,
      success: func,
      crossDomain: true,
      type: "POST",
      complete: function() {
        $("#ajax_loading").hide();
      }
    };
    if (postData) {
      ajaxOptions.data = JSON.stringify(postData);
    }
    $.ajax(
      ajaxOptions
    );
  }

  /**
   * pops uo the message window , showing header as window header and message as the content of the dialog
   */
  function showMessage(header, message) {
    $("#lock_background_trans").show();
    $(".message-dialog").show();
    $(".message-dialog-header").html(header);
    $(".message-dialog-content").html(message);
  }

  /**
   * Call listClusters lambda to get cluster list
   * @param {string} nextToken : aws styl paging , if server has more data it attached a token to returned object
   */
  function loadClusterList(nextToken) {
    clusterData = {};
    var url = apiRootUrl + "/listClusters";
    var postData = {};
    if (nextToken) {
      postData = {};
      postData.nextToken = nextToken;
    }
    ajaxCall(url, function(data) {
      $("#cList").empty(); //clear cluster list
      uiGenerateClusterHeader().appendTo($("#cList")); //add header fields
      if (!data) { //no data
        setClusterListEventHandlers();
        return;
      }
      clusterData = data; //we cache cluster not to call the api again for otherui elements 
      activeNodeCount = 0; //reset cluster count
      data.clusters.forEach(function(cluster) { //every node that is not deleted consumes xcalar license??
        if (cluster.fields["status"] != "Deleted") {
          activeNodeCount++; //bookkeeping for license text
        }
        //  uiGenerateClusterRow(cluster).appendTo($("#cList")); //for each cluster generate a row in cluster grid
        setClusterListEventHandlers();
      })
      if (data.NextToken) { //if more data to be consumed from server , keep pulling it
        loadClusterList(data.NextToken)
      }
    }, postData);
  }

  /**
   * returns a uuid
   */
  function uuidv4() {
    return ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, c =>
      (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
    )
  }

  /**
   * 
   * @param {string} name 
   * name of the cluster 
   * @param {integer} count
   * number of nodes in cluster
   * @param {string} action [create / start] 
   * create a cluster given parameters or start a deleted cluster shich is already in DB
   * if start is passed , backend lambda ignores the passed params and use params stored for the same cluster in db
   */
  function provisionCluster(name, count, action) {
    var errorString ="";
    if (name.trim() === "") {
      errorString += "Cluster name is missing<br>";
    }
    if(parseInt(count) >10 || parseInt(count)<=0 || isNaN(parseInt(count))){
      errorString += "Number of nodes should be between 1 and 10<br>";
    }
    if(!clusterInstanceType.selected){
      errorString += "Instance type is not selected.<br>";
    }
    if(errorString !=""){
      showMessage("Critical Error",errorString) ;
      return;
    }
    clusterInstanceType
    name = name + "-" + suffix;
    var LambdaRole = $("#LambdaRole").val();
    var cfnTemplate = {
      "RoleARN": LambdaRole,
      "StackName": name,
      "Capabilities": [
        "CAPABILITY_IAM"
      ],
      "ClientRequestToken": uuidv4(),
      "DisableRollback": false,
      "EnableTerminationProtection": false,
      "Parameters": [{
          "ParameterKey": "LicenseKey",
          "ParameterValue": $("#license-text").val()
        },
        {
          "ParameterKey": "InstanceCount",
          "ParameterValue": count.toString()
        }
      ]
    }
    //construct the post data with settings in the ui
    $(".settingWidget").each(function(index) {
      var id = $(this).attr('id');
      if (!ignoreList.includes(id)) {
        var param = {
          "ParameterKey": id,
          "ParameterValue": $(this).val()
        }
        if (id == "InstanceType") {
          param["ParameterValue"] = clusterInstanceType.selected;
          clusterInstanceType.reset();
        }
        cfnTemplate.Parameters.push(param);
      }
    });
    var postData = {
      stackName: name,
      action: action,
      cfnTemplate: cfnTemplate //cloudformation template parameters to create stack
    }
    var url = apiRootUrl + "/createCluster";
    ajaxCall(url, function(data) {
      if (data.errorString) {
        showMessage("Critical Error", data.errorString);
      } 
    }, postData);
      $(".cluster-provision-dialog").hide();
      $("#lock_background").hide();
  }
  /**
   * 
   * @param {string} name name of the cluster to apply delete action
   * @param {string } action "delete" or "stop" , action is used when the same cluster is provisioned
   */
  function deleteCluster(name, action) {
    var postData = {
      "name": name,
      "action": action
    }
    var url = apiRootUrl + "/deleteCluster";
    ajaxCall(url, function(data) {
      if (data.errorString) {
        showMessage("Critical Error", data.errorString);
      }
    }, postData);
  }

  /**
   * parses xcalar license and reflects results to ui elemenets
   */
  function parseXcalarLicense() {
    var licenseItems = decompress($("#license-text").val()).split("\n");
    licenseHash = {};
    licenseItems.forEach(function(line) {
      tokens = line.split("=");
      licenseHash[tokens[0]] = tokens[1];
    })
    $(".licensed-to").text("Licensed To: " + licenseHash["LicensedTo"]);
    $(".number-of-nodes").text("Number of Nodes: " + licenseHash["NodeCount"]);
    $(".license-expiration").text("Expiration Date: " + licenseHash["ExpirationDate"]);
    $(".licensed-nodes").text("Licensed Nodes: (" + activeNodeCount + "/" + licenseHash["NodeCount"] + ")");
  }


  function setEventHandlers() {
    //little arrow in cluster details modal that shows and hides node ips
    $(".cluster-nodes-expand").click(function(e) {
      if ($(".cluster-detail-item-list2").is(":visible")) {
        $(".cluster-detail-item-list2").hide();
        $(".cluster-nodes-expand").removeClass("icon-xi-arrow-up");
        $(".cluster-nodes-expand").addClass("icon-xi-arrow-down");
        $(".node-list-container").removeClass("cluster-detail-item-list");
        $(".node-list-container").addClass("cluster-detail-item");
      } else {
        $(".cluster-detail-item-list2").show();
        $(".cluster-nodes-expand").removeClass("icon-xi-arrow-down");
        $(".cluster-nodes-expand").addClass("icon-xi-arrow-up");
        $(".node-list-container").addClass("cluster-detail-item-list");
        $(".node-list-container").removeClass("cluster-detail-item");
      }
    });
    //if class hint-available added to any element , hover shows the hint
    $(".hint-available").hover(function() {
        $("#hintBox").html(helpData[hintKey]);
        $("#hintBox").show();
        pos = $(this).offset();
        pos.left += 20;
        pos.top += 20;
        $("#hintBox").offset(pos);
        var hintKey = $(this).attr("data-hint-key");
        if (hintKey in helpData) {
          $("#hintBox").html(helpData[hintKey]);
          $("#hintBox").show();
        } else {
          var hint = $(this).attr("data-hint"); //no hash 
          if (hint) {
            $("#hintBox").html(hint);
          }
        }
      },
      function() {
        $("#hintBox").hide();
      }
    );
    //little help buttons , nothing is implemented for click yet , for future
    $(".helpButton").click(function(e) {;
    });
    //button that opens and close cluster area
    $(".show-hide-clusters").click(function(e) {
      if ($(".cluster-panel").is(":visible")) {
        $(".cluster-panel").hide();
        $(".show-hide-clusters").removeClass("icon-xi-up");
        $(".show-hide-clusters").addClass("icon-xi-down");
      } else {
        $(".show-hide-clusters").removeClass("icon-xi-down");
        $(".show-hide-clusters").addClass("icon-xi-up");
        $(".cluster-panel").show();
      }
    });
    //button that opens and close settings area
    $(".show-hide-settings").click(function(e) {
      if ($(".settings-panel").is(":visible")) {
        $(".settings-panel").hide();
        $(".show-hide-settings").removeClass("icon-xi-up");
        $(".show-hide-settings").addClass("icon-xi-down");
      } else {
        $(".show-hide-settings").removeClass("icon-xi-down");
        $(".show-hide-settings").addClass("icon-xi-up");
        $(".settings-panel").show();
      }
    });
    //license preview button on license modal
    $(".license-preview-button").click(function(e) {
      if ($(".license-preview").is(":visible")) {
        $(".license-preview").hide();
        $(".license-info").width("100%");
      } else {
        $(".license-info").width("50%")
        $(".license-preview").show();
        $(".licensed-to").text("Licensed To: N/A");
        $(".number-of-nodes").text("Number of Nodes: N/A");
        $(".license-expiration").text("Expiration Date: N/A");
        parseXcalarLicense();
      }
    });
    //license update button on license modal
    $(".license-update-button").click(function(e) {
      $(".licensed-to").text("Licensed To: N/A");
      $(".number-of-nodes").text("Number of Nodes: N/A");
      $(".license-expiration").text("Expiration Date: N/A");
      parseXcalarLicense();
      savePage(".settingWidget");
    });
    //generic close button (little x on the right top corner)
    $(".close-button").click(function(e) {
      $(".modal-dialog").hide();
      $("#lock_background").hide();
    });
    //create cluster button in cluster provisioning modal
    $(".provision-cluster-button").click(function(e) {
      $(".cluster-provision-dialog").show();
      $("#lock_background").show();
    });
    //update license button in main page, not the one in the modal
    $(".update-license-btn").click(function(e) {
      $(".license-dialog").show();
      $("#lock_background").show();
    });
    //save settings button
    $("#btnSaveSettings").click(function(e) {
      savePage(".settingWidget")
    });
    //restore settings button
    $("#btnRestorePrevious").click(function(e) {
      loadPage(".settingWidget")
    });
    //provision cluster button in cluster provisioning modal
    $("#btnModalProvision").click(function(e) {
      var instanceCount = parseInt($("#pNumberOfNodes").val());
      var clusterName = $("#pClusterName").val();
      var config = {
        "op": $("#pMode").val(),
        "xcalarRoot": $("#pXcalarRoot").val(),
        "version": $("#pClusterName").val()
      }
      provisionCluster(clusterName, instanceCount, "create");
      loadClusterList();
    });
    //hide custom dropdowns if clicked somewhere else
    $('*').click(function(e) {
      if (!$(e.target).hasClass("custom-select")) {
        $(".custom-select-items-container").hide();
      }
    });
    //hide message dialog 
    $('.close-message-dialog').click(function(e) {
      $(".message-dialog").hide();
      $("#lock_background_trans").hide();
    });
  }

  /**
   * gets the selected cluster names from ui and apply the action
   * @param {string} action : actionto apply selected clusters 
   */
  function clusterAction(action) {
    clusters = [];
    action = action.toLowerCase();
    $('input:checkbox').each(function() {
      var sThisVal = (this.checked ? $(this).val() : "");
      if ($(this).attr('data-cluster-name') != "checkbox" && sThisVal) {
        clusters.push($(this).attr('data-cluster-name'));
      }
    });
    clusters.forEach(function(name) {
      deleteCluster(name, action);
    });
    clusterActionSelect.reset();
  }

  /**
   * needs to be run once for every refresh
   * mostly about hiding dialogs and a few div resizing
   * it also sets the timer for auto refresh
   */

  function init() {
    $(".modalContainer").show();
    setInterval(function() {
      loadClusterList();
    }, 30000)
    $(".settings-panel").hide();
    $("#ajax_loading").hide();
    $(".select-items-container").hide();
    $(".modal-dialog").hide();
    $("#lock_background").hide();
    $(".license-preview").hide();
    $("#hintBox").hide();


    $(".license-info").width("100%");
    uiGenerateClusterHeader().appendTo($("#cList"));
    setEventHandlers();
    //sortClusterList("clusterName");
  }

  /**
   * takes a class , iterates all elems for given class , construct a json for dynamoDB
   * posts it to db
   * 
   * className : class of html elems that ll be saved
   */
  function savePage(className) {
    data = {
      ID: "settings",
      elems: []
    }
    $(className).each(function(index) {
      var val = $(this).val();
      if ($(this).is(':radio') || $(this).is(':checkbox')) {
        if ($(this).is(':checked')) {
          val = "1";
        } else {
          val = "0";
        }
      }
      if (val) {
        data.elems.push({
          "id": $(this).attr("id"),
          "value": val
        });
      }
    });
    var url = apiRootUrl + "/postToDB";
    var postData = data;
    ajaxCall(url, function(data) {
      if (data.errorString) {
        showMessage("Critical Error", data.errorString);
      }
    }, postData);
  }

  /**
   * get elem dat from dynamo
   * set values of the corresponding elems
   */
  function loadPage() {
    var url = apiRootUrl + "/getFromDB";
    var postData = {
      "ID": "settings"
    };
    ajaxCall(url, function(data) {
      if (!data.Item) {
        savePage(".settingWidget");
        return;
      } else {
        data.Item.elems.forEach(function(el) {
          if ($("#" + el.id).is(':radio') || $("#" + el.id).is(':checkbox')) {
            if (el.value == "1") {
              $("#" + el.id).prop('checked', true);
            } else {
              $("#" + el.id).prop('checked', false);
            }
          }
          $("#" + el.id).val(el.value)
        });
        try {
          parseXcalarLicense();
        } catch (errorStr) {
          showMessage("Critical Error", errorStr);

        };

        if (data.errorString) {
          showMessage("Critical Error", data.errorString);
        }
      }
    }, postData);
  }
  var clusterInstanceType = new CustomSelect($(".cluster-instance-type"), [
    "m5.xlarge",
    "m5.2xlarge",
    "m5.4xlarge",
    "m5.12xlarge",
    "m5.24xlarge",
    "c5.2xlarge",
    "c5.4xlarge",
    "c5.9xlarge",
    "c5.18xlarge",
    "r4.2xlarge",
    "r4.4xlarge",
    "r4.8xlarge",
    "r4.16xlarge",
    "i3.large",
    "i3.xlarge",
    "i3.2xlarge",
    "i3.4xlarge",
    "i3.8xlarge",
    "i3.16xlarge",
    "x1.16xlarge",
    "x1.32xlarge"
  ], "select_item", function(sel) {;});
  var clusterActionSelect = new CustomSelect($(".cluster-action-wrapper"), ["Delete", "Start", "Stop"], "Action for selected", function(sel) {
    clusterAction(sel);
  });
  generateSettings(settings_data);
  init();
  if (UNIT_TESTING) {
    clusterData.clusters.forEach(function(cluster) {
      uiGenerateClusterRow(cluster).appendTo($("#cList"));
    })
  }
}