//
//Currently only handles one table per page due to these global variables.
//
var dataTableGlobal = [];
var dataTableSearchText = [];
var dataTableOnAQuest = [];
$(document).ready(function() { setupDataTables();  });

function setupDataTables()
{
	$(".tablesorter").each(function(index){
        if($(this).prop("tablerendered")) // Short circuit if we've already initialized this table
        {
            return;
        }
        $(this).prop("tablerendered", "rendered");
		console.log("Adding Datatable");
        var thisID = $(this).attr('id');
		var dataTableInitialize = ""+
				"dataTableGlobal['"+thisID+"'] = $(this).DataTable("+
				"{" +
				"'jQueryUI': true,"+
			    "'sPaginationType': 'full_numbers',"+
			    "'lengthMenu': [[10, 25, 50, -1], [10, 25, 50, 'All']],"+
			    "columns: [";
			    
		$(this).find("th").each(function(index2){
			dataTableInitialize+="{data: '"+$(this).html()+"'},";
		});
		dataTableInitialize+="]}); dataTableOnAQuest['"+thisID+"'] = 0;";
		console.log(dataTableInitialize);
		//Need to make it adapt to all tables on the UI
		eval(dataTableInitialize);
		
		$(this).on( 'search.dt', function () {
            if(!dataTableOnAQuest[thisID]) // Let's not double up on the server, wait for the previous search to finish
            {
                var text = dataTableGlobal[thisID].search();
                // Prevent infinite loop
                if(text != dataTableSearchText[thisID] && (text.length > 1))
                {
                    var path = location.protocol+"//"+location.hostname;
                    var uri = $("#thisURI").val();
                    var returnURL = path+"/index.php?getjson=1&"+uri;
                    var moreURI = "&searchtable="+thisID+"&additionalsearch=1&searchstring="+text;
                    console.log("sending search "+returnURL+moreURI);
                    dataTableSearchText[thisID]=text;
                    dataTableOnAQuest[thisID] = 1;
                    $.getJSON(returnURL+moreURI,function(data){
                        dataTableOnAQuest[thisID] = 0;
                        //We only want to add rows that are not already there
                        var somethingChanged = false;
                        for (i = 0; i < data.length; i++) 
                        {
                            var found=false;
                            var theTable = dataTableGlobal[thisID].data();
                            for(b = 0; b < theTable.length; b++)
                            {
                                if(!found)
                                {
                                    found = compareObjects(theTable[b], data[i]);
                                }
                            }
                            if(!found)
                            {
                                //$(".debugWindow").append("adding "+data[i].NUM+"<br />");
                                dataTableGlobal[thisID].row.add(data[i]);
                                somethingChanged = true;
                            }
                        }
                        if(somethingChanged) //Only redraw if there was new data added to the table
                        {
                            dataTableGlobal[thisID].draw();
                        }
                    });
                }
            }
			
		});
	});
}

function compareObjects(o1, o2)
{
    for(var p in o1)
    {
        if( p in o2 )
        {
// console.log("Comparing: '" + o1[p] +"' to '"+ o2[p] + "'");
            if( ''+o1[p] != ''+o2[p])
            {
                return false;
            }
        }
        else
        {
            return false;
        }
    }
    for(var p in o2)
    {
        if( p in o1 )
        {
// console.log("Comparing: '" + o1[p] +"' to '"+ o2[p] + "'");
            if(''+o1[p] != ''+o2[p])
            {
                return false;
            }
        }
        else
        {
            return false;
        }
    }
    return true;
};
