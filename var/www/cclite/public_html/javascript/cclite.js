 


function stripe() {
     striper('tbody','stripy', 'tr', 'odd,even') ;
}

/* controlling statistics, mail transactions and csv file transactions
  for the system, the intervals must be set here for the moment
*/

stats_interval_id = 0 ;
mail_interval_id = 0 ;
csv_interval_id = 0 ;
rss_interval_id = 0 ;
gammu_interval_id = 0 


 function on_select_change(id){
     // #stats_value, #mail_value etc
     selector = '#' + eval("id") + '_value' ;
     var selected = $(selector + " option:selected");       
     var output = "";  
     if(selected.val() != 0){  
         output = "You Selected " + selected.val();  
     }
     
   control_task (id,selected.val())  ;
 }  



/* experimental general input processing, value supplied by select as minutes
changed into milliseconds here */

function control_task (type,minutes) {
    
  // alert((type + ' ' + minutes)) ;
   
   //selector is used to change the status bar selection
   selector = '#' + eval("type") ;
  
   interval = eval("type") + '_interval' ;
   window[interval] = minutes * 60 * 1000  
  
   interval_display = '#' + interval ;
   interval_id = eval("type") + '_interval_id' ;
    
  if (minutes == 0) { 
       clearInterval ( window[interval_id] );
       $(selector).html('Stopped ' + type);
       $(selector).css('background-color', 'red');
       window[type]  = "stopped" ;
  } else if (minutes > 0) {
      try{
       $(selector).html('Starting ' + type );
       // display run interval in seconds
       display_interval =  minutes ;
       window[type] = "started" ;
       $(selector).css('color', 'white');
       $(selector).css('background-color', 'darkorange');  
       
     // window[interval_id] = setInterval( "do_task('type', 'batch_path')", window[interval]) ;
     
     // this ugly thing is something to do with scoping in setInterval, go figure, I can't!
     if (type == 'stats') {
       window[interval_id] = setInterval( "do_task( 'stats', '/cgi-bin/protected/graphs/graph.pl')", window[interval]) ;
      } else if (type == 'rss') {
       window[interval_id] = setInterval( "do_task( 'rss', '/cgi-bin/protected/batch/writerss.pl')", window[interval]) ;
      } else if (type == 'mail') {
        window[interval_id] = setInterval( "do_task( 'mail', '/cgi-bin/protected/batch/read_pop_mail.pl')", window[interval]) ;
      } else if (type == 'csv') {
        window[interval_id] = setInterval( "do_task( 'csv', '/cgi-bin/protected/batch/readcsv.pl')", window[interval]) ;
      } else if (type == 'gammu') {
      window[interval_id] = setInterval( "do_task( 'gammu', '/cgi-bin/protected/batch/readsms_from_gammu.pl')", window[interval]) ;               
     }
                            
                 
       //alert('time ' + window[interval] + ' id ' + window[interval_id] + ' ' + interval_id) ;
       } catch(error) { alert('error is ' + error)}
      
  }

}


/* Running appears next to the button  in selector and the data appears below the buttons in status_selector
can be used to transmit errors from the script into the page */


function do_task(type,batch_path)
{
 
     //alert('batch path ' + batch_path) ;
   
     try{
     selector = '#' + eval("type") ;
     status_selector = '#' + eval("type") + '_status' ;
     $(selector).html('Processing ' + type);
     $(selector).css('background-color', 'green');
      $.ajax({
                    method: 'get',
                    url : batch_path,
                    dataType : 'text',
                    success: function (data) { $(selector).html('Running ' + type) ; $(status_selector).html(data);
                    }
                 });
      // reload graphs for stats only
      if (type == 'stats') {
       // why doesn't jquery selection work here? sigh   
       vol = document.getElementById('volumes').src ;
       trans = document.getElementById('transactions').src ;
       document.getElementById('volumes').src = vol + '?' + (new Date()).getTime() ;
       document.getElementById('transactions').src = trans + '?' + (new Date()).getTime() ;
     }
      
      $(selector).html('Waiting ' + type);
     } catch(error) { alert('error is ' + error)}
}

var newwindow;
function poptastic(url)
{
	newwindow=window.open(url,'_blank','');
	if (window.focus) {newwindow.focus()}
}

  

 $(document).ready(function(){


 
 // $('.menu *').tooltip();
 //  poptastic('/cgi-bin/protected/ccadmin.cgi') ;
 
// show logoff if logon, show admin link in user, if admin, needs to be multilingual
   if ($.cookie('userLogin')  ) {    
     $('#userlink').html("Cclite User");
     logoff = 'Log off '  + $.cookie('userLogin') ;
     $("#logoff").html(logoff);     
   }
   
// show admin menu link, if administrator
   if ($.cookie('userLevel') == 'admin') {
      $("#adminlink").html("Admin Menu");
      $("#adminlinknewtab").html("*");
     }
//alert($("#fileproblems").length) ;

  if ($("#fileproblems").length > 1){
     
    $("#fileliteral").html('Batch files or directories below have problems, put mouse over to examine') ;
  }
   

// prompt for cut and paste of configuration if not writable directly
   $("#copydiv").bind('copy', function(e) {
                alert('Now paste this into cclite\.cf');
            });
   
   $('#stats').css('color', 'white');
   $('#mail').css('color', 'white');
   $('#csv').css('color', 'white'); 
   $('#rss').css('color', 'white');
   $('#gammu').css('color', 'white');
  
  $("#form").validate();


 






  
	$("#demo1_box")
		.bind( "dragstart", function( event ){
			// ref the "dragged" element, make a copy
			var $drag = $( this ), $proxy = $drag.clone();
			// modify the "dragged" source element
			$drag.addClass("outline");
			// insert and return the "proxy" element		
			return $proxy.appendTo( document.body ).addClass("ghost");
			})
		.bind( "drag", function( event ){
			// update the "proxy" element position
			$( event.dragProxy ).css({
				left: event.offsetX, 
				top: event.offsetY
				});
			})
		.bind( "dragend", function( event ){
			// remove the "proxy" element
			$( event.dragProxy ).fadeOut( "normal", function(){
				$( this ).remove();
				});
			// if there is no drop AND the target was previously dropped 
			if ( !event.dropTarget && $(this).parent().is(".drop") ){
				// output details of the action
				$('#log').append('<div>Removed <b>'+ this.title +'</b> from <b>'+ this.parentNode.title +'</b></div>');
				// put it in it's original <div>
				$('#nodrop').append( this );
				}
			// restore to a normal state
			$( this ).removeClass("outline");	
			
			});
	$('.drop')
		.bind( "dropstart", function( event ){
			// don't drop in itself
			if ( this == event.dragTarget.parentNode ) return false;
			// activate the "drop" target element
			$( this ).addClass("active");
			})
                
		.bind( "drop", function( event ){
			// if there was a drop, move some data...
			$( this ).append( event.dragTarget );
			// output details of the action...
			$('#log').append('<div>Dropped <b>'+ event.dragTarget.title +'</b> into <b>'+ this.title +'</b></div>');
                        $.ajax({
                              type: "POST",
                              url: "/cgi-bin/protected/graphs/graph_new.pl",
                              data: "",
                              success: function(msg){
                                          alert( "Data Saved: " + msg );
                                   }
                              });

			})
		.bind( "dropend", function( event ){
			// deactivate the "drop" target element
			$( this ).removeClass("active");
			});
/*
    $.jheartbeat.set({
      url: “”, // The URL that jHeartbeat will retrieve
      delay: 1500, // How often jHeartbeat should retrieve the URL
     div_id: “test_div” // Where the data will be appended.
      , function (){
     // Callback Function
     }
     );
     });


*/


 $("#tradeDestination").autocomplete("/cgi-bin/ccsuggest.cgi",
{
   extraParams: {
       type: function() { return 'user' ; }
   }
}); 


  $("#string1").autocomplete("/cgi-bin/ccsuggest.cgi",

{
   extraParams: {
       type: function() { return 'user' ; }
   }

});


  $("#nuserLogin").autocomplete("/cgi-bin/ccsuggest.cgi",

{
   extraParams: {
       type: function() { return 'newuser' ; }
   }

});


  $("#string2").autocomplete("/cgi-bin/ccsuggest.cgi",
{
   extraParams: {
       type: function() { return 'ad' ; }
   }


});
  $("#string3").autocomplete("/cgi-bin/ccsuggest.cgi",

{
   extraParams: {
       type: function() { return 'trade' ; }
   }

});

 
  });

