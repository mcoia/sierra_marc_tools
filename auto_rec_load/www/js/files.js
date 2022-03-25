$(document).ready(function() {
    getFilesTable($('#files_summary_datatable'));
});

function getFilesTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"></div>');
    var querystring = {'getsummarytable': '1'};
    var url = createServerCallBackURL(querystring);
    $.get(url,
        function(data){
            wrapperdiv.html(data);
            setupDataTables();
    });
}

function marcFileDownloadClick(fileid, element)
{
    var source = "";
    var querystring = {'fileid': fileid};
    
    if($(element).attr("sourcefile") !== undefined)
    {
        querystring['sourcefile'] = '1';
    }

    var url = createServerCallBackURL(querystring, 'getmarc');

    window.location.assign(url);
    return false;
}
