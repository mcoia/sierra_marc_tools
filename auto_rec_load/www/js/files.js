$(document).ready(function() {
    getFilesTable($('#files_summary_datatable'));
});

function getFilesTable(wrapperdiv)
{
    wrapperdiv.append('<div class="loader"</div>');
    var pageID = "pageid="+$("#thisPageID").val();
    var path = location.protocol+"//"+location.hostname;
    var fromDate = '';
    var url = path+"/index.php?getdata=1" + fromDate + "&getsummarytable=1&"+pageID;
    console.log("Getting data: "+url);
    $.get(url,
        function(data){
            wrapperdiv.html(data);
            setupDataTables();
    });
}

function marcFileDownloadClick(fileid, element)
{
    var path = location.protocol+"//"+location.hostname;
    var source = "";
    if($(element).attr("sourcefile") !== undefined)
    {
        source = "&sourcefile=1";
    }

    var url = path+"/index.php?getmarc=1&fileid="+fileid+source;

    console.log("Getting data: "+url);
    window.location.assign(url);
    return false;
}
