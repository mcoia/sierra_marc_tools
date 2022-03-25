$(document).ready(function() {
    getNoticeTables($('#notice_definition_datatable'), 'gettemplatetable');
    getNoticeTables($('#notice_history_datatable'), 'gethistorytable');
    $('#create_notice_definition_button').click(function(){createNoticeDefinitionDialog();});
});

function getNoticeTables(wrapperdiv, tableType)
{
    wrapperdiv.append('<div class="loader"></div>');
    var querystring = {};
    if($('#datesince'))
    {
        querystring['fromdate'] = convertStringToDate($('#datesince').val());
    }
    querystring[tableType] = '1';
    var url = createServerCallBackURL(querystring);
    $.get(url,
        function(data){
            wrapperdiv.html(data);
            setupDataTables();
    });
}

function createNoticeDefinitionDialog(editingID = 0, chosenSource = -1, chosenName = null, chosenEnabled = null, chosenType = null, chosenStatus = null, template = null)
{
    createOverlayDialog(getFormModal(editingID, chosenSource, chosenName, chosenEnabled, chosenType, chosenStatus, template));
    wireSubmitForm(editingID);
}

function createSourceDropdown(chosenVal)
{
    if(chosenVal == null) // convert to a string becaues null is a valid option
    {
        chosenVal ='null';
    }

    var ret = '<select id="noticeSourceDropdown"><option name="Choose one:">Choose one:</option>';
    for(var i=0; i<sourceList.length; i++)
    {
        var composedName = sourceList[i]['sourcename'] + '_' + sourceList[i]['clientname'];
        var id = sourceList[i]['id'];
        var chosen = '';
        if(chosenVal == id)
        {
            chosen = 'selected = "chosen"';
        }
        ret += '<option ' + chosen + ' name="' + id + '">' + composedName + '</option>';
    }
    ret += '</select>';
    return ret;
}

function createDropdown(dropdownType, chosenVal, used)
{
    var ret = '<select id="notice' + dropdownType + 'Dropdown"><option name="Choose one:">Choose one:</option>';
    for(var i=0; i<noticeMetadata[dropdownType].length; i++)
    {
        var chosen = '';
        var thisAllowed = 1;
        if(chosenVal == noticeMetadata[dropdownType][i])
        {
            chosen = 'selected = "chosen"';
        }
        if(used && used.length > 0)
        {
            for(var j=0; j<used.length; j++)
            {
                if(noticeMetadata[dropdownType][i] == used[j])
                {
                    thisAllowed = 0; // Already used
                }
            }
        }
        if(thisAllowed)
        {
            ret += '<option ' + chosen + ' name="' + noticeMetadata[dropdownType][i] + '">' + noticeMetadata[dropdownType][i] + '</option>';
        }
    }
    ret += '</select>';
    return ret;
}

function getFormModal(editingID = 0, chosenSource = -1, chosenName = null, chosenEnabled = null, chosenType = null, chosenStatus = null, template = null)
{
    var typesDropdown = createDropdown('types', chosenType);
    var statusesDropdown = createDropdown('upon_statuses', chosenStatus);
    var sourceDropdown = createSourceDropdown(chosenSource);
    var name = chosenName !== null ? chosenName : "";
    var enabled = chosenEnabled !== null ? chosenEnabled : "";
    enabled = enabled + "" == '0' ? "" : "checked='checked'";
    var title = "Create New Notice Definition";
    title = editingID > 0 ? "Editing Existing Definition" : title;
    var defaultHeader = "From: noreply@mobiusconsortium.org\n" +
    "To: mcohelp@mobiusconsortium.org\n" +
    "Cc: noreply@mobiusconsortium.org\n" +
    "Subject: Record Load Notice\n\n";

    defaultHeader = (template !== null && template.length > 0) ? template : defaultHeader;

    var ret = "<div class=\"title\">" + title + "</div>" +
    "<div style=\"width: 50%;padding:2em\">" +
    "<div class=\"titlesmaller floatleft\">Name</div>" +
    "<div id=\"noticeNameWrapper\" class=\"floatright\"><input type=\"text\" id=\"noticeNameInputBox\" value=\""+name+"\"></input></div><div class=\"clearthis\"></div>" +
    "</div>" +
    "<div style=\"width: 50%;padding:2em\">" +
    "<div class=\"titlesmaller floatleft\">Enabled</div>" +
    "<div id=\"noticeEnabledWrapper\" class=\"floatright\"><input id=\"noticeEnabledCheckBox\" type=\"checkbox\" name=\"noticeEnabledCheckBox\" "+enabled+" ></div><div class=\"clearthis\"></div>" +
    "</div>" +
    "<div style=\"width:50%;padding:2em\">" +
    "<div class=\"titlesmaller floatleft\">Vendor/Client</div>" +
    "<div id=\"noticeSourceWrapper\" class=\"floatright\">" + sourceDropdown + "</div><div class=\"clearthis\"></div>" +
    "</div>" +
    "<div style=\"width:50%;padding:2em\">" +
    "<div class=\"titlesmaller floatleft\">Notice Type</div>" +
    "<div id=\"noticeTypeWrapper\" class=\"floatright\">" + typesDropdown + "</div><div class=\"clearthis\"></div>" +
    "</div>" +
    "<div style=\"width:50%;padding:2em\">" +
    "<div class=\"titlesmaller floatleft\">Notice Upon Status</div>" +
    "<div id=\"noticeStatusWrapper\" class=\"floatright\">" + statusesDropdown + "</div><div class=\"clearthis\"></div>" +
    "</div>" +
    "<div class=\"titlesmaller\">Notice Template</div>" +
    "<div id=\"noticeTemplateWrapper\"><textarea id=\"noticeTemplateData\">"+defaultHeader+"</textarea></div>";


    // Submit button
    ret += "<input noticeID=\"" + editingID + "\" id=\"noticeSubmitButton\" type=\"submit\" value=\"Submit\" />";

    return ret;
}

function wireSubmitForm(editingID = 0)
{
    if(editingID > 0)
    {
        $("#noticeSourceDropdown").prop("disabled", true);
        $("#noticetypesDropdown").prop("disabled", true);
        $("#noticeupon_statusesDropdown").prop("disabled", true);
    }
    else
    {
        // Remove some of the dropdown menus until the user has selected an option
        $("#noticeStatusWrapper").html('');
        $("#noticeTypeWrapper").html('');
        $("#noticeSourceDropdown").change(function(){ sourceChanged() });
    }
    $("#noticeSubmitButton").click(function(){submitNotice()});
}

function submitNotice()
{
    if(validate())
    {
        console.log("Successful Validation");

        var source = getSelectedItemName('#noticeSourceDropdown');
        var type = getSelectedItemName('#noticetypesDropdown');
        var upon_status = getSelectedItemName('#noticeupon_statusesDropdown');
        var editingID =  $("#noticeSubmitButton").attr('noticeID');
        var enabled =  $("#noticeEnabledCheckBox").is(':checked');

        var template = $("#noticeTemplateData").val();
        var name = $("#noticeNameInputBox").val();

        var querystring = {'submittemplate': '1'};
        var url = createServerCallBackURL(querystring);

        $.post(url,
        {
            'editingID' : editingID,
            'name' : name,
            'enabled' : enabled,
            'source' : source,
            'type' : type,
            'upon_status' : upon_status,
            'template' : htmlEscape(template)
        } ).done(
            function(data){
                if(data == '1')
                {
                    overlayDialogMessage("Success", 'success');
                    $("#overlaydialogresponsemessage").fadeOut(2000, function(){
                        location.reload();
                        });
                }
                else
                {
                    overlayDialogMessage("Error, maybe you've alrady defined a notice for this scenario? " + data);
                }
                console.log(data);
        }, 'json');
    }
}

function validate()
{
    console.log("validating");
    overlayDialogMessage("");
    var nonZeroLengthFields = ['noticeNameInputBox', 'noticeTemplateData'];
    var dropdowns = ['noticeSourceDropdown', 'noticeupon_statusesDropdown', 'noticetypesDropdown'];
    var errors = "";
    var ret = 1;
    for(var i=0; i < nonZeroLengthFields.length; i++)
    {
        var thisElement = $("#"+nonZeroLengthFields[i]);
        if(thisElement.val().length < 1)
        {
            thisElement.css('background-color', 'red');
            errors +="We need at least one character in highlighted boxes<br />";
        }
        else
        {
            thisElement.css('background-color', '');
        }
        console.log($("#"+nonZeroLengthFields[i]).val());
    }
    for(var i=0; i < dropdowns.length; i++)
    {
        var thisElement = $("#"+dropdowns[i]);
        if(!thisElement)
        {
            errors +="We need at a value for " + dropdowns[i] + "<br />";
        }
        else if(getSelectedItemName('#'+dropdowns[i]) == 'Choose one:')
        {
            thisElement.css('background-color', 'red');
            errors +="Please choose an item from the highlight dropdown<br />";
        }
        else
        {
            thisElement.css('background-color', '');
        }
    }
    if(errors.length > 0)
    {
        overlayDialogMessage(errors);
        ret = 0;
    }
    return ret;
}

function getUsedOptions(sourceID, type)
{
    var ret = [];
    for(var i=0; i < noticeMetadata["used_templates"].length; i++)
    {
        if(noticeMetadata["used_templates"][i]["sourceid"]+"" == sourceID+"") // Stringify the two values so that "null" will match null
        {
            if(noticeMetadata["used_templates"][i]["type"] == type)
            {
                ret.push(noticeMetadata["used_templates"][i]["upon_status"]);
            }
        }
    }
    return ret;
}

function getChosenOption(templateID, dropdownType)
{
    for(var i=0; i < noticeMetadata["used_templates"].length; i++)
    {
        if(noticeMetadata["used_templates"][i]["id"] == templateID)
        {
            return noticeMetadata["used_templates"][i][dropdownType];
        }
    }
    return 0;
}

function sourceChanged()
{
    $("#noticeStatusWrapper").html('');
    var typeDropdown = createDropdown('types');
    $("#noticeTypeWrapper").html(typeDropdown);
    $("#noticetypesDropdown").change(function(){ typeChanged() });
    
}

function getSelectedItemName(domID)
{
    return $(domID).find(":selected").attr('name');
}

function typeChanged()
{
    var source = getSelectedItemName('#noticeSourceDropdown');
    var type = getSelectedItemName('#noticetypesDropdown');
    console.log("source = " + source);
    console.log("type = " + type);
    var usedTypeUponStatus = getUsedOptions(source, type);
    var statusDropdown = createDropdown('upon_statuses', undefined, usedTypeUponStatus);
    $("#noticeStatusWrapper").html(statusDropdown);
}

function templateAction(action, templateID)
{
    var source = getChosenOption(templateID, 'sourceid');
    var type = getChosenOption(templateID, 'type');
    var upon_status = getChosenOption(templateID, 'upon_status');
    var enabled = getChosenOption(templateID, 'enabled');
    var name = getChosenOption(templateID, 'name');
    var template = "";
    var querystring = {};
    if(action == 'edit' || action == 'clone')
    {
        if(source !== 0 && type !== 0 && upon_status !== 0)
        {
            querystring['gettemplateid'] = templateID;
            var url = createServerCallBackURL(querystring);
            $.get(url,
                function(data){
                    template = data;
                    if(action == 'clone')
                    {
                        createNoticeDefinitionDialog(0, -1, null, null, null, null, template);
                    }
                    else
                    {
                        createNoticeDefinitionDialog(templateID, source, name, enabled, type, upon_status, template);
                    }
            });
        }
    }
    else if(action == 'delete')
    {
        let text;
        if (confirm("Are you sure you would like to delete this template and all of it's history?") == true)
        {
            console.log("Deleting: "+templateID);
            querystring['deletetemplate'] = templateID;
            var url = createServerCallBackURL(querystring);
            $.get(url,
                function(data){
                    if(data == '1')
                    {
                        location.reload();
                    }
                    else
                    {
                        alert("Failed to delete");
                    }
            });
        }
        else
        {
            console.log("Not Deleting: "+templateID);
        }
    }
}

function historyAction(action, historyID)
{
    if(action == 'emailme')
    {
        createOverlayDialog(
        "<div class=\"titlesmaller\">Provide comma separated email addresses</div>"+
        "<input type=\"text\" style=\"width:75%\" id=\"emailmeEmailInput\"></input><br />"+
        "<input historyID=\"" + historyID + "\" id=\"emailMeSubmitButton\" type=\"submit\" value=\"Submit\" />"
        );
        $("#emailMeSubmitButton").click(function(){
            if($("#emailmeEmailInput").val().length > 0)
            {
                var querystring = {
                    'emailme': historyID,
                    'emailmeaddress': encodeURIComponent( $("#emailmeEmailInput").val() )
                    };
                
                var url = createServerCallBackURL(querystring);
                $.get(url,
                function(data){
                    if(data == '1')
                    {
                        overlayDialogMessage("Email queued", 'success');
                    }
                    else
                    {
                        overlayDialogMessage("Server had a issue creating the request: " + data);
                    }
                });
                
            }
            else
            {
                overlayDialogMessage("Please provide at least one email address");
            }
        });
    }
}