$(document).ready(function() { 
	makeDateDropdowns();
});

function makeDateDropdowns()
{
	$('.date').each(function(index){
		var id = $(this).attr('id');
		 $( '#'+id ).datepicker(
				 {dateFormat: 'mm-dd-yy'}
				 );
		//$('#'+id).datepick({dateFormat: 'mm-dd-yyyy'});
	});
}