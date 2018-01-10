//# sourceURL=J_KSENIA.js
// This program is free software: you can redistribute it and/or modify
// it under the condition that it is for private or home useage and 
// this whole comment is reproduced in the source code file.
// Commercial utilisation is not authorized without the appropriate
// written agreement from amg0 / alexis . mermet @ gmail . com
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

//-------------------------------------------------------------
// ksenia  Plugin javascript Tabs
//-------------------------------------------------------------
var ksenia_Svs = 'urn:upnp-org:serviceId:ksenia1';
var ip_address = data_request_url;

if (typeof String.prototype.format == 'undefined') {
	String.prototype.format = function()
	{
		var args = new Array(arguments.length);

		for (var i = 0; i < args.length; ++i) {
			// `i` is always valid index in the arguments object
			// so we merely retrieve the value
			args[i] = arguments[i];
		}

		return this.replace(/{(\d+)}/g, function(match, number) { 
			return typeof args[number] != 'undefined' ? args[number] : match;
		});
	};
};

//-------------------------------------------------------------
// Device TAB : Donate
//-------------------------------------------------------------	
function ksenia_Donate(deviceID) {
	var htmlDonate='For those who really like this plugin and feel like it, you can donate what you want here on Paypal. It will not buy you more support not any garantee that this can be maintained or evolve in the future but if you want to show you are happy and would like my kids to transform some of the time I steal from them into some <i>concrete</i> returns, please feel very free ( and absolutely not forced to ) to donate whatever you want.  thank you ! ';
	htmlDonate+='<form action="https://www.paypal.com/cgi-bin/webscr" method="post" target="_top"><input type="hidden" name="cmd" value="_donations"><input type="hidden" name="business" value="alexis.mermet@free.fr"><input type="hidden" name="lc" value="FR"><input type="hidden" name="item_name" value="Alexis Mermet"><input type="hidden" name="item_number" value="ksenia"><input type="hidden" name="no_note" value="0"><input type="hidden" name="currency_code" value="EUR"><input type="hidden" name="bn" value="PP-DonationsBF:btn_donateCC_LG.gif:NonHostedGuest"><input type="image" src="https://www.paypalobjects.com/en_US/FR/i/btn/btn_donateCC_LG.gif" border="0" name="submit" alt="PayPal - The safer, easier way to pay online!"><img alt="" border="0" src="https://www.paypalobjects.com/fr_FR/i/scr/pixel.gif" width="1" height="1"></form>';
	var html = '<div>'+htmlDonate+'</div>';
	set_panel_html(html);
}

//-------------------------------------------------------------
// Device TAB : Settings
//-------------------------------------------------------------	

function ksenia_Settings(deviceID) {
	var debug  = get_device_state(deviceID,  ksenia_Svs, 'Debug',1);
	var credentials = get_device_state(deviceID,  ksenia_Svs, 'Credentials',1);
	var poll = get_device_state(deviceID,  ksenia_Svs, 'RefreshPeriod',1);
	var pin = ""

	// get_device_state(deviceID,  ksenia_Svs, 'PIN',1);
	var html =
    '                                                           \
      <div id="ksenia-settings">                                           \
        <form class="row" id="ksenia-settings-form">                        \
					<div class="form-group col-6 col-xs-6">																	\
						<label for="ksenia-username">User Name</label>		\
						<input type="text" class="form-control" id="ksenia-username" placeholder="User">	\
					</div>																										\
					<div class="form-group col-6 col-xs-6">																	\
						<label for="ksenia-pwd">Password</label>			\
						<input type="password" class="form-control" id="ksenia-pwd" placeholder="Password">	\
					</div>																								\
					<div class="form-group col-6 col-xs-6">																	\
						<label for="ksenia-RefreshPeriod">Polling in sec</label>			\
						<input type="number" min="1" max="15" class="form-control" id="ksenia-RefreshPeriod" placeholder="5">	\
					</div>																								\
					<div class="form-group col-6 col-xs-6">																	\
						<label for="ksenia-PIN">PIN code</label>			\
						<input type="number" pattern="\\d{6,6}" class="form-control" id="ksenia-PIN" placeholder="------">	\
					</div>																								\
					<button id="ksenia-submit" type="submit" class="btn btn-default">Submit</button>	\
				</form>                                                 \
      </div>                                                    \
    '		
	set_panel_html(html);
	
	getPIN(deviceID,function(pin) {
		var arr = atob(credentials).split(":");
		jQuery( "#ksenia-PIN" ).val(pin)
		jQuery( "#ksenia-username" ).val(arr[0]);
		jQuery( "#ksenia-pwd" ).val(arr[1]);
		jQuery( "#ksenia-RefreshPeriod" ).val(poll);
		jQuery( "#ksenia-PIN" ).val(pin);
		
		jQuery( "#ksenia-settings-form" ).on("submit", function(event) {
			event.preventDefault();
			var usr = jQuery( "#ksenia-username" ).val();
			var pwd = jQuery( "#ksenia-pwd" ).val();
			var poll = jQuery( "#ksenia-RefreshPeriod" ).val();
			var pin = jQuery( "#ksenia-PIN" ).val();
			
			var encode = btoa( "{0}:{1}".format(usr,pwd) );
			saveVar( deviceID,  ksenia_Svs, "Credentials", encode, 0 )
			saveVar( deviceID,  ksenia_Svs, "RefreshPeriod", poll, 0 )
			savePIN( deviceID, pin ).done( function() {
				jQuery("#ksenia-submit").addClass('btn-success');
			});

			return false;
		});
	})
}

//-------------------------------------------------------------
// Device TAB : Scenario
//-------------------------------------------------------------	
function ksenia_Scenario(deviceID) {
	function refreshPartitions(deviceID) {
		var partitions = JSON.parse( get_device_state(deviceID,  ksenia_Svs, 'Partitions',1) );
		$.each(partitions, function(k,part) {
			var cls= 'btn-info';
			switch (part.status) {
				case 'ARMED_IMMEDIATE':
					cls='btn-danger'; break;
				case 'DISARMED':
					cls='btn-success'; break;
				default:
					cls='btn-warning'; break;
			}
			jQuery("button#ksenia-{0}-{1}".format(deviceID,part.id)).removeClass('btn-danger btn-warning btn-info').addClass(cls);
		});
		setTimeout( refreshPartitions, 2000, deviceID );
	}

	var partitions = JSON.parse( get_device_state(deviceID,  ksenia_Svs, 'Partitions',1) );
	var tmp   = get_device_state(deviceID,  ksenia_Svs, 'Scenarios',1);
	var scenario = JSON.parse(tmp);
	var html = '<div id="ksenia-scenario">'
	html += '<div class="row">'
		html += '<div class="col-xs-6 col-6">'
			html += "<h3>Scenario</h3>"
		html += '</div>'
		html += '<div class="col-xs-6 col-6">'
			html += "<h3>Partitions</h3>"
		html += '</div>'
	html += '</div>'
	html += '<div class="row">'
		html += '<div class="col-xs-6 col-6">'
		jQuery.each( scenario, function(key,val) {
			html += '<button type="button" id="ksenia-scen-{1}" class="ksenia-scenario-btn btn btn-default btn-default btn-block">{0}</button>'.format(key,val.id)
		});
		html += '</div>'
		html += '<div class="col-xs-6 col-6">'
		$.each(partitions, function(k,part) {
			var cls= 'btn-info';
			html += '<button id="ksenia-{2}-{3}" type="button" class="btn btn-block disabled {1}">{0}</button>'.format(k,cls,deviceID,part.id)
		});
		html += '</div>'
	html += '</div>'
	set_panel_html(html);
	refreshPartitions(deviceID);

	jQuery(".ksenia-scenario-btn").click( function(event) {
		var id = jQuery(this).prop('id');
		var name = jQuery(this).text();
		var url = buildUPnPActionUrl(deviceID,ksenia_Svs,"RunScenario",{ scenarioName: name });
		jQuery(".ksenia-scenario-btn").removeClass('btn-success btn-warning');
		jQuery.ajax({
			type: "GET",
			url: url,
			cache: false,
		}).done(function() {
			jQuery("#"+id).addClass('btn-success');
			setTimeout(function(id) {
				jQuery("#"+id).removeClass('btn-success');
			},1000,id)
		}).fail(function() {
			alert('Run Scenario Failed');
			jQuery(".ksenia-scenario-btn#"+id).addClass('btn-warning');
		});
	});
}

//-------------------------------------------------------------
// Device TAB : Information
//-------------------------------------------------------------	
function ksenia_Information(deviceID) {
	var info = JSON.parse( get_device_state(deviceID,  ksenia_Svs, 'Information',1) );
	var html="<div class='col-xs-12 col-12'>";
	html += "<table class='table'>"
	html += "<thead>"
	html += "<tr>"
	html += "<th>Col"
	html += "</th>"
	html += "<th>Val"
	html += "</th>"
	html += "</tr>"
	html += "</thead>"
	html += "<tbody>"
	var keys = Object.keys(info).sort()
	jQuery.each(keys, function(key,value) {
		html += "<tr>"
		html += "<td>"
		html += value
		html += "</td>"
		html += "<td>"
		html += info[value]
		html += "</td>"
		html += "</tr>"		
	});
	html += "</tbody>"
	html += "</table>"
	html +="</div>"
	set_panel_html(html);
}

//-------------------------------------------------------------
// Device TAB : Settings
//-------------------------------------------------------------	
function ksenia_Events(deviceID) {
	var html="<div class='col-xs-12 col-12'>";
	html += "<table id='ksenia_eventtbl' class='table'>"
	html += "</table>"
	html +="</div>"
	set_panel_html(html);
	
	var url = buildHandlerUrl(deviceID,"GetEvents",{dummy:'test'} );
	jQuery.ajax({
		type: "GET",
		url: url,
		cache: false,
	})
	.done( function(info) {
		var cols = ["data","time","event","means","generator","id"]
		if (info && info.length>0) {
			var html = "";
			var first = info[0];
			html += "<thead>"
			html += "<tr>"
			html += "<th>Type</th>"
			jQuery.each(cols, function(key,col) {
				html += "<th>{0}</th>".format(col)
			})
			html += "</tr>"
			html += "</thead>"
			html += "<tbody>"
			jQuery.each(info, function(key,value) {
				var val = value.trace;
				var css = (value.type>2) ? "text-warning" : "text-primary"
				html += "<tr>"
				html += "<td>"
				html += value.type
				html += "</td>"
				jQuery.each(cols, function(key,col) {
					html += "<td><span class='{1}'>{0}</span></td>".format(val[col] || '',css)
				})
				html += "</tr>"		
			});
			html += "</tbody>"
			jQuery("#ksenia_eventtbl").html(html);
		}
	})
}

//-------------------------------------------------------------
// Variable saving ( log , then full save )
//-------------------------------------------------------------
function saveVar(deviceID,  service, varName, varVal, reload)
{
	set_device_state(deviceID, ksenia_Svs, varName, varVal, 0);	// lost in case of luup restart
}

function getPIN(deviceID,cbfunc)
{
	var url = buildHandlerUrl(deviceID,"GetPIN",{ } )
	jQuery.get(url)
		.done(function(data) {
			if (jQuery.isFunction(cbfunc)) {
				(cbfunc)(data);
			} 
		})
		.fail(function() {
			alert( "Get Pin failed" );
		})
}

function savePIN(deviceID, varVal)
{
	var url = buildHandlerUrl(deviceID,"SetPIN",{ PinCode: varVal } )
	return jQuery.get(url)
		.fail(function() {
			alert( "Set Pin failed" );
		})
}


//-------------------------------------------------------------
// Helper functions to build URLs to call VERA code from JS
//-------------------------------------------------------------

function buildUPnPActionUrl(deviceID,service,action,params)
{
	var urlHead = ip_address +'id=action&output_format=json&DeviceNum='+deviceID+'&serviceId='+service+'&action='+action;//'&newTargetValue=1';
	if (params != undefined) {
		jQuery.each(params, function(index,value) {
			urlHead = urlHead+"&"+index+"="+value;
		});
	}
	return urlHead;
}

function buildHandlerUrl(deviceID,command,params)
{
	//http://192.168.1.5:3480/data_request?id=lr_IPhone_Handler
	var urlHead = ip_address +'id=lr_KSENIA_Handler&command='+command+'&DeviceNum='+deviceID;
	jQuery.each(params, function(index,value) {
		urlHead = urlHead+"&"+index+"="+encodeURIComponent(value);
	});
	return encodeURI(urlHead);
}
