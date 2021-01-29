let instanceCount = 0;

function CustomSelect(target, items, placeHolder, onChange) {
    instanceCount++;
    this.instanceName = "CustomSelect" + instanceCount;
    this.placeHolder = placeHolder;
    this.reset = function() {
        $("#" + this.instanceName + "_default").html(this.placeHolder);
        $("#" + this.instanceName + "_default").addClass("action-selected");
        $("#" + this.instanceName + "_default").removeClass("custom-drop-selected");
        this.selected = "";
    }
    this.onChange = onChange;
    var instanceName = "CustomSelect" + instanceCount;
    var skeleton = "<div class=\"band custom-select\"> \
    <div id =\"" + instanceName + "_default\" class=\"band action-selected custom-select\">" + placeHolder + "</div> \
    <div class=\"drop-arrow-wrapper " + instanceName + "_button custom-select\"> \
        <div id =\"" + instanceName + "_button\" class=\"custom-select show-hide-actions icon-xi-arrow-down font-button-plus\"></div>\
    </div>\
    </div>"
    var itemsDiv = $("<div id=\"" + instanceName + "_itemsDiv\" class=\"custom-select custom-select-items-container\"></div>");
    itemsDiv.appendTo($('#xcmDiv'));
    var id = 0;
    var ref = this;
    items.forEach(element => {
        var itemHTML = "<div id=\"" + instanceName + "_item" + id + "\" data-target-value=\"" + element + "\" class=\"custom-select select-item cluster-action\">" + element + "</div>";
        $(itemHTML).appendTo(itemsDiv);
        $("#" + instanceName + "_item" + id).click(
            function() {
                $("#" + instanceName + "_itemsDiv").hide();
                $("#" + instanceName + "_default").html($(this).html());
                $("#" + instanceName + "_default").removeClass("action-selected");
                $("#" + instanceName + "_default").addClass("custom-drop-selected");
                ref.selected = $(this).html();
                ref.onChange(ref.selected);
            }
        );
        id++;
    });
    $(skeleton).appendTo(target);
    itemsDiv.hide();
    $("." + instanceName + "_button").click(function(e) {
        var defaultDiv = $("#" + instanceName + "_default");
        itemsDiv.width(defaultDiv.width() * 2);
        itemsDiv.show();
        pos = defaultDiv.offset();
        pos.top += 37;
        itemsDiv.offset(pos);
    });
    $(".select-item").hover(
        function() {
            $(this).removeClass("select-item");
            $(this).addClass("select-item-hover");
        },
        function() {
            $(this).removeClass("select-item-hover");
            $(this).addClass("select-item");
        }
    );
}