-- // This program is free software: you can redistribute it and/or modify
-- // it under the condition that it is for private or home useage and 
-- // this whole comment is reproduced in the source code file.
-- // Commercial utilisation is not authorized without the appropriate
-- // written agreement from amg0 / alexis . mermet @ gmail . com
-- // This program is distributed in the hope that it will be useful,
-- // but WITHOUT ANY WARRANTY; without even the implied warranty of
-- // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE . 
local MSG_CLASS = "KSENIA"
local KSENIA_SERVICE = "urn:upnp-org:serviceId:ksenia1"
local devicetype = "urn:schemas-upnp-org:device:ksenia:1"
local this_device = nil
local DEBUG_MODE = false	-- controlled by UPNP action
local version = "v0.3"
local UI7_JSON_FILE= "D_KSENIA_UI7.json"
local DEFAULT_REFRESH = 5
local json = require("dkjson")
local hostname = nil

local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local lom = require("lxp.lom") -- http://matthewwild.co.uk/projects/luaexpat/lom.html
local xpath = require("xpath")

-- local mime = require("mime")
-- local https = require ("ssl.https")
-- local modurl = require "socket.url"

------------------------------------------------
-- Debug --
------------------------------------------------
function log(text, level)
	luup.log(string.format("%s: %s", MSG_CLASS, text), (level or 50))
end

function debug(text)
	if (DEBUG_MODE) then
		log("debug: " .. text)
	end
end

function warning(stuff)
	log("warning: " .. stuff, 2)
end

function error(stuff)
	log("error: " .. stuff, 1)
end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

local function isempty(s)
  return s == nil or s == ''
end

---code from lolodomo DNLA plugin
local function xml_decode(val)
      return val:gsub("&#38;", '&')
                :gsub("&#60;", '<')
                :gsub("&#62;", '>')
                :gsub("&#34;", '"')
                :gsub("&#39;", "'")
                :gsub("&lt;", "<")
                :gsub("&gt;", ">")
                :gsub("&quot;", '"')
                :gsub("&apos;", "'")
                :gsub("&amp;", "&")
end

---code from lolodomo DNLA plugin
local function xml_encode(val)
      return val:gsub("&", "&amp;")
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
                :gsub('"', "&quot;")
                :gsub("'", "&apos;")
end
	
local function findTHISDevice()
	for k,v in pairs(luup.devices) do
		if( v.device_type == devicetype ) then
			return k
		end
	end
	return -1
end

------------------------------------------------
-- Device Properties Utils
------------------------------------------------

local function getSetVariable(serviceId, name, deviceId, default)
	local curValue = luup.variable_get(serviceId, name, deviceId)
	if (curValue == nil) then
		curValue = default
		luup.variable_set(serviceId, name, curValue, deviceId)
	end
	return curValue
end

local function getSetVariableIfEmpty(serviceId, name, deviceId, default)
	local curValue = luup.variable_get(serviceId, name, deviceId)
	if (curValue == nil) or (curValue:trim() == "") then
		curValue = default
		luup.variable_set(serviceId, name, curValue, deviceId)
	end
	return curValue
end

local function setVariableIfChanged(serviceId, name, value, deviceId)
	debug(string.format("setVariableIfChanged(%s,%s,%s,%s)",serviceId, name, value, deviceId))
	local curValue = luup.variable_get(serviceId, name, tonumber(deviceId)) or ""
	value = value or ""
	if (tostring(curValue)~=tostring(value)) then
		luup.variable_set(serviceId, name, value, tonumber(deviceId))
	end
end

local function setAttrIfChanged(name, value, deviceId)
	debug(string.format("setAttrIfChanged(%s,%s,%s)",name, value, deviceId))
	local curValue = luup.attr_get(name, deviceId)
	if ((value ~= curValue) or (curValue == nil)) then
		luup.attr_set(name, value, deviceId)
		return true
	end
	return value
end

local function getIP()
	-- local stdout = io.popen("GetNetworkState.sh ip_wan")
	-- local ip = stdout:read("*a")
	-- stdout:close()
	-- return ip
	local mySocket = socket.udp ()  
	mySocket:setpeername ("42.42.42.42", "424242")  -- arbitrary IP/PORT  
	local ip = mySocket:getsockname ()  
	mySocket: close()  
	return ip or "127.0.0.1" 
end

------------------------------------------------
-- Check UI7
------------------------------------------------
local function checkVersion(lul_device)
	local ui7Check = luup.variable_get(KSENIA_SERVICE, "UI7Check", lul_device) or ""
	if ui7Check == "" then
		luup.variable_set(KSENIA_SERVICE, "UI7Check", "false", lul_device)
		ui7Check = "false"
	end
	if( luup.version_branch == 1 and luup.version_major == 7 and ui7Check == "false") then
		luup.variable_set(KSENIA_SERVICE, "UI7Check", "true", lul_device)
		luup.attr_set("device_json", UI7_JSON_FILE, lul_device)
		luup.reload()
	end
end

local function getSysinfo(ip)
	--http://192.168.1.5/cgi-bin/cmh/sysinfo.sh
	log(string.format("getSysinfo(%s)",ip))
	local url=string.format("http://%s/cgi-bin/cmh/sysinfo.sh",ip)
	local timeout = 30
	local httpcode,content = luup.inet.wget(url,timeout)
	if (httpcode==0) then
		local obj = json.decode(content)
		debug("sysinfo="..content)
		return obj
	end
	return nil
end

------------------------------------------------
-- Tasks
------------------------------------------------
local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

--
-- Has to be "non-local" in order for MiOS to call it :(
--
local function task(text, mode)
	if (mode == TASK_ERROR_PERM)
	then
		error(text)
	elseif (mode ~= TASK_SUCCESS)
	then
		warning(text)
	else
		log(text)
	end
	if (mode == TASK_ERROR_PERM)
	then
		taskHandle = luup.task(text, TASK_ERROR, MSG_CLASS, taskHandle)
	else
		taskHandle = luup.task(text, mode, MSG_CLASS, taskHandle)

		-- Clear the previous error, since they're all transient
		if (mode ~= TASK_SUCCESS)
		then
			luup.call_delay("clearTask", 15, "", false)
		end
	end
end

function clearTask()
	task("Clearing...", TASK_SUCCESS)
end

function UserMessage(text, mode)
	mode = (mode or TASK_ERROR)
	task(text,mode)
end

------------------------------------------------
-- LUA Utils
------------------------------------------------
local function Split(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gmatch(str, pat) do
        nb = nb + 1
        result[nb] = part
        lastPos = pos
        if nb == maxNb then break end
    end
    -- Handle the last field
    if nb ~= maxNb then
        result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function string:split(sep) -- from http://lua-users.org/wiki/SplitJoin   : changed as consecutive delimeters was not returning empty strings
	return Split(self, sep)
	-- local sep, fields = sep or ":", {}
	-- local pattern = string.format("([^%s]+)", sep)
	-- self:gsub(pattern, function(c) fields[#fields+1] = c end)
	-- return fields
end


function string:template(variables)
	return (self:gsub('@(.-)@', 
		function (key) 
			return tostring(variables[key] or '') 
		end))
end

function string:trim()
  return self:match "^%s*(.-)%s*$"
end

------------------------------------------------
-- VERA Device Utils
------------------------------------------------

local function tablelength(T)
  local count = 0
  if (T~=nil) then
	for _ in pairs(T) do count = count + 1 end
  end
  return count
end

local function getParent(lul_device)
	return luup.devices[lul_device].device_num_parent
end

local function getAltID(lul_device)
	return luup.devices[lul_device].id
end

-----------------------------------
-- from a altid, find a child device
-- returns 2 values
-- a) the index === the device ID
-- b) the device itself luup.devices[id]
-----------------------------------
local function findChild( lul_parent, altid )
	-- debug(string.format("findChild(%s,%s)",lul_parent,altid))
	for k,v in pairs(luup.devices) do
		if( getParent(k)==lul_parent) then
			if( v.id==altid) then
				return k,v
			end
		end
	end
	return nil,nil
end

------------------------------------------------
-- HOUSE MODE
------------------------------------------------
-- 1 = Home
-- 2 = Away
-- 3 = Night
-- 4 = Vacation
local HModes = { "Home", "Away", "Night", "Vacation" ,"Unknown" }

local function setHouseMode( newmode ) 
	debug(string.format("HouseMode, setHouseMode( %s )",newmode))
	newmode = tonumber(newmode)
	if (newmode>=1) and (newmode<=4) then
		debug("SetHouseMode to "..newmode)
		luup.call_action('urn:micasaverde-com:serviceId:HomeAutomationGateway1', 'SetHouseMode', { Mode=newmode }, 0)
	end
end

local function getMode() 
	debug("HouseMode, getMode()")
	-- local url_req = "http://" .. getIP() .. ":3480/data_request?id=variableget&DeviceNum=0&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&Variable=Mode"
	local url_req = "http://127.0.0.1:3480/data_request?id=variableget&DeviceNum=0&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&Variable=Mode"
	local req_status, req_result = luup.inet.wget(url_req)
	-- ISSUE WITH THIS CODE=> ONLY WORKS WITHIN GLOBAL SCOPE LUA, not in PLUGIN context
	-- debug("calling getMode()...")
	-- local req_result =  luup.attr_get("Mode")
	-- debug("getMode() = "..req_result)
	req_result = tonumber( req_result or (#HModes+1) )
	log(string.format("HouseMode, getMode() returns: %s, %s",req_result or "", HModes[req_result]))
	return req_result , HModes[req_result]
end

------------------------------------------------
-- Communication TO KSENIA system
------------------------------------------------
local function KSeniaHttpCall(lul_device,cmd)
	lul_device = tonumber(lul_device)
	log(string.format("KSeniaHttpCall(%d,%s)",lul_device,cmd))

	local credentials= getSetVariable(KSENIA_SERVICE,"Credentials", lul_device, "")
	local ip_address = luup.attr_get ('ip', lul_device )
	
	if (ipaddr=="") then
		warning(string.format("IPADDR is not initialized"))
		return nil
	end
	if (credentials=="") then
		warning("Missing credentials for Ksenia device :"..lul_device,TASK_BUSY)
		return nil
	end	
	
	local myheaders={}
	if (credentials~=nil)then
		local b64credential = "Basic ".. credentials
		myheaders={
			--["Accept"]="text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
			["Authorization"]=b64credential, --"Basic " + b64 encoded string of user:pwd
		}
	end
	local url = string.format ("http://%s/%s", ip_address,cmd)
	debug("url:"..url)
	debug("myheaders:"..json.encode(myheaders))
	
	local result = {}
	local request, code = http.request({
		url = url,
		headers = myheaders,
		sink = ltn12.sink.table(result)
	})
	
	-- fail to connect
	if (request==nil) then
		error(string.format("failed to connect to %s, http.request returned nil", ip_address))
		return nil
	elseif (code==401) then
		warning(string.format("Access to KSENIA requires a user/password: %d", code))
		return "unauthorized"
	elseif (code~=200) then
		warning(string.format("http.request returned a bad code: %d", code))
		return nil
	end
	
	-- everything looks good
	local data = table.concat(result)
	debug(string.format("request:%s",request))	
	debug(string.format("code:%s",code))	
	debug(string.format("data:%s",data))	
	return data
end

------------------------------------------------------------------------------------------------
-- Http handlers : Communication FROM ALTUI
-- http://192.168.1.5:3480/data_request?id=lr_KSENIA_Handler&command=xxx
-- recommended settings in ALTUI: PATH = /data_request?id=lr_KSENIA_Handler&mac=$M&deviceID=114
------------------------------------------------------------------------------------------------
function switch( command, actiontable)
	-- check if it is in the table, otherwise call default
	if ( actiontable[command]~=nil ) then
		return actiontable[command]
	end
	log("KSENIA_Handler:Unknown command received:"..command.." was called. Default function")
	return actiontable["default"]
end

function myKSENIA_Handler(lul_request, lul_parameters, lul_outputformat)
	debug('myKSENIA_Handler: request is: '..tostring(lul_request))
	debug('myKSENIA_Handler: parameters is: '..json.encode(lul_parameters))
	-- debug('KSENIA_Handler: outputformat is: '..json.encode(lul_outputformat))
	local lul_html = "";	-- empty return by default
	local mime_type = "";
	-- debug("hostname="..hostname)
	if (hostname=="") then
		hostname = getIP()
		debug("now hostname="..hostname)
	end
	
	-- find a parameter called "command"
	if ( lul_parameters["command"] ~= nil ) then
		command =lul_parameters["command"]
	else
	    debug("KSENIA_Handler:no command specified, taking default")
		command ="default"
	end
	
	local deviceID = this_device or tonumber(lul_parameters["DeviceNum"] or findTHISDevice() )
	
	-- switch table
	local action = {
		["default"] = 
			function(params)	
				return "default handler / not successful", "text/plain"
			end
	}
	-- actual call
	lul_html , mime_type = switch(command,action)(lul_parameters)
	if (command ~= "home") and (command ~= "oscommand") then
		debug(string.format("lul_html:%s",lul_html or ""))
	end
	return (lul_html or "") , mime_type
end


------------------------------------------------
-- UPNP actions Sequence
------------------------------------------------
local function UserSetArmed(lul_device,newArmedValue)
	log(string.format("UserSetArmed(%s,%s)",lul_device,newArmedValue))
	lul_device = tonumber(lul_device)
	newArmedValue = tonumber(newArmedValue)
	return luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", newArmedValue, lul_device)
end

local function setDebugMode(lul_device,newDebugMode)
	lul_device = tonumber(lul_device)
	newDebugMode = tonumber(newDebugMode) or 0
	log(string.format("setDebugMode(%d,%d)",lul_device,newDebugMode))
	luup.variable_set(KSENIA_SERVICE, "Debug", newDebugMode, lul_device)
	if (newDebugMode==1) then
		DEBUG_MODE=true
	else
		DEBUG_MODE=false
	end
end

local function runScenario(lul_device,scenarioName)
	log(string.format("runScenario(%s,%s)",lul_device,scenarioName))
	lul_device = tonumber(lul_device)
	local tmp = getSetVariable(KSENIA_SERVICE, "Scenarios", lul_device, "[]")
	local pin = getSetVariable(KSENIA_SERVICE, "PIN", lul_device, "")
	
	local scenarios = json.decode(tmp)
	if ( scenarios[ scenarioName ] ~= nil ) then
		local pinstr = ""
		if (scenarios[ scenarioName ].nopin == "FALSE") then
			pinstr = "&pin="..pin
		end
		local url = "xml/cmd/cmdOk.xml?cmd=setMacro"..pinstr.."&macroId=".. scenarios[ scenarioName ].id .. "&redirectPage=/xml/cmd/cmdError.xml"
		local xmlstatus = KSeniaHttpCall(lul_device,url)
	end
	return true
end

------------------------------------------------
-- STARTUP Sequence
------------------------------------------------

local function registerHandlers()
	luup.register_handler("myKSENIA_Handler","KSENIA_Handler")
end

function refreshEngineCB(lul_device)
	lul_device = tonumber(lul_device)
	debug(string.format("refreshEngineCB(%s)",lul_device))
	
	local xmlstatus = KSeniaHttpCall(lul_device,"xml/zones/zonesStatus16IP.xml")
	local lomtab2 = lom.parse(xmlstatus)
	local statuses = xpath.selectNodes(lomtab2,"//zone/status/text()")
	for k,v in pairs(statuses) do
		-- k is the index 'zone'k  in altid
		local idx,dev = findChild( lul_device, "zone"..k )
		if (idx ~= nil) then
			local value = 0
			if (v=="NORMAL") then
				value = 0
			elseif (v=="ALARM") then
				value = 1
			end
			local oldtripped = getSetVariable("urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", idx, 0)
			local armed = getSetVariable("urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", idx, 0)
			oldtripped = tonumber(oldtripped)
			armed = tonumber(armed)
			if (oldtripped ~= value) then
				luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", value, idx)
				if (value==1) then
					luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", os.time(), idx)
					if (armed==1) then
						setVariableIfChanged("urn:micasaverde-com:serviceId:SecuritySensor1", "ArmedTripped", value, idx)
					end
				else
					luup.variable_set("urn:micasaverde-com:serviceId:SecuritySensor1", "LastUntrip", os.time(), idx)
					setVariableIfChanged("urn:micasaverde-com:serviceId:SecuritySensor1", "ArmedTripped", 0, idx)
				end
			-- else
				-- debug(string.format("device:%s, same old and new value:%s %s", idx, v,value))
			end
		end
	end
	
	--
	-- refresh Partition Status
	--
	local partitions = json.decode( getSetVariable(KSENIA_SERVICE, "Partitions", lul_device, "[]") )
	local xmlStatus = KSeniaHttpCall(lul_device,"xml/partitions/partitionsStatus16IP.xml") 
	lomtab = lom.parse(xmlStatus)
	local statuses = xpath.selectNodes(lomtab,"//partition/text()")
	local bChanged = false
	
	for k,v in pairs(partitions) do
		if (partitions[k].status ~= statuses[ v.id +1 ]) then
			bChanged = true
			partitions[k].status = statuses[ v.id +1 ]
		end
	end
	if (bChanged==true) then
		luup.variable_set(KSENIA_SERVICE, "Partitions", json.encode(partitions), lul_device)
	end
	
	local period= getSetVariable(KSENIA_SERVICE, "RefreshPeriod", lul_device, DEFAULT_REFRESH)
	luup.call_delay("refreshEngineCB",period,tostring(lul_device))
end

local function createChildren(lul_device,zones)
	debug(string.format("createChildren(%s,%s)",lul_device,json.encode(zones)))
	-- for all children device, iterate
    local child_devices = luup.chdev.start(lul_device);
	local devtype = "urn:schemas-micasaverde-com:device:MotionSensor:1"
	local devfile = "D_MotionSensor1.xml"
	for k,v in pairs(zones) do
		luup.chdev.append(
			lul_device, child_devices, 
			"zone"..k, zones[k], 
			devtype,devfile,  
			"", "", 
			false		-- embedded
			)
	end
	luup.chdev.sync(lul_device, child_devices)
end

local function loadKSeniaData(lul_device)
	debug(string.format("loadScenario(%s)",lul_device))
	--
	-- scenarios
	--
	local xmlDescr = KSeniaHttpCall(lul_device,"xml/scenarios/scenariosDescription.xml")
	local lomtab = lom.parse(xmlDescr)
	local scenarios = xpath.selectNodes(lomtab,"//scenario/text()")
	
	local xmlOptions= KSeniaHttpCall(lul_device,"xml/scenarios/scenariosOptions.xml")
	lomtab = lom.parse(xmlOptions)
	local abils = xpath.selectNodes(lomtab,"//scenario/abil/text()")
	local nopins = xpath.selectNodes(lomtab,"//scenario/nopin/text()")

	local tbl = {}
	for k,v in ipairs(scenarios) do
		if (abils[k] == "TRUE") then
			tbl[v] = {
				id = tonumber(k)-1,
				nopin=nopins[k]
			}
		end
	end
	luup.variable_set(KSENIA_SERVICE, "Scenarios", json.encode(tbl), lul_device)

	--
	-- Partitions
	--
	local xmlPartitions= KSeniaHttpCall(lul_device,"xml/partitions/partitionsDescription16IP.xml")
	lomtab = lom.parse(xmlPartitions)
	local partitions = xpath.selectNodes(lomtab,"//partition/text()")
	local xmlStatus = KSeniaHttpCall(lul_device,"xml/partitions/partitionsStatus16IP.xml") 
	lomtab = lom.parse(xmlStatus)
	local statuses = xpath.selectNodes(lomtab,"//partition/text()")
	tbl = {}
	for k,v in ipairs(partitions) do
		if (v ~= "" ) then
			tbl[v] = {
				id = tonumber(k)-1,
				status = statuses[k]
			}
		end
	end
	luup.variable_set(KSENIA_SERVICE, "Partitions", json.encode(tbl), lul_device)
	
	--
	-- Power
	--
	local xmlFaults= KSeniaHttpCall(lul_device,"xml/faults/faults.xml")
	lomtab = lom.parse(xmlFaults)
	
	local power =  xpath.selectNodes(lomtab,"//powerSupply/voltage/text()")
	local battery = xpath.selectNodes(lomtab,"//battery/voltage/text()")
	power = tonumber(power[1])
	battery = tonumber(battery[1])
	if (power~=0) then
		luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel", math.floor( battery*100/power) , lul_device)
		luup.variable_set("urn:micasaverde-com:serviceId:HaDevice1", "BatteryDate", os.time(), lul_device)
	end
	return true
end

local function startEngine(lul_device)
	debug(string.format("startEngine(%s)",lul_device))

	local xmldata = KSeniaHttpCall(lul_device,"xml/zones/zonesDescription16IP.xml")
	if (xmldata ~= nil) then
		local period= getSetVariable(KSENIA_SERVICE, "RefreshPeriod", lul_device, DEFAULT_REFRESH)
		local lomtab = lom.parse(xmldata)
		local zones = xpath.selectNodes(lomtab,"//zone/text()")
		debug("zones:"..json.encode(zones))
		createChildren(lul_device, zones )
		luup.call_delay("refreshEngineCB",period,tostring(lul_device))
		return loadKSeniaData(lul_device)
	else
		warning(string.format("missing ip addr or credentials"))
	end
	return false
end

function startupDeferred(lul_device)
	lul_device = tonumber(lul_device)
	log("startupDeferred, called on behalf of device:"..lul_device)

	local debugmode = getSetVariable(KSENIA_SERVICE, "Debug", lul_device, "0")
	local oldversion = getSetVariable(KSENIA_SERVICE, "Version", lul_device, version)
	local credentials  = getSetVariable(KSENIA_SERVICE, "Credentials", lul_device, "")
	local pin  = getSetVariable(KSENIA_SERVICE, "PIN", lul_device, "")
	local period= getSetVariable(KSENIA_SERVICE, "RefreshPeriod", lul_device, DEFAULT_REFRESH)
	-- local ipaddr = luup.attr_get ('ip', lul_device )

	if (debugmode=="1") then
		DEBUG_MODE = true
		UserMessage("Enabling debug mode for device:"..lul_device,TASK_BUSY)
	end
	local major,minor = 0,0
	local tbl={}
	
	if (oldversion~=nil) then
		major,minor = string.match(oldversion,"v(%d+)%.(%d+)")
		major,minor = tonumber(major),tonumber(minor)
		debug ("Plugin version: "..version.." Device's Version is major:"..major.." minor:"..minor)

		newmajor,newminor = string.match(version,"v(%d+)%.(%d+)")
		newmajor,newminor = tonumber(newmajor),tonumber(newminor)
		debug ("Device's New Version is major:"..newmajor.." minor:"..newminor)
		
		-- force the default in case of upgrade
		if ( (newmajor>major) or ( (newmajor==major) and (newminor>minor) ) ) then
			log ("Version upgrade => Reseting Plugin config to default")
		end
		luup.variable_set(KSENIA_SERVICE, "Version", version, lul_device)
	end	
	
	-- start handlers
	registerHandlers()

	-- start engine
	local success = false
	success = startEngine(lul_device)
	
	-- NOTHING to start 
	if( luup.version_branch == 1 and luup.version_major == 7) then
		if (success == true) then
			luup.set_failure(0,lul_device)	-- should be 0 in UI7
		else
			luup.set_failure(1,lul_device)	-- should be 0 in UI7
		end
	else
		luup.set_failure(false,lul_device)	-- should be 0 in UI7
	end

	log("startup completed")
end
		
function initstatus(lul_device)
	lul_device = tonumber(lul_device)
	this_device = lul_device
	log("initstatus("..lul_device..") starting version: "..version)	
	checkVersion(lul_device)
	math.randomseed( os.time() )
	hostname = getIP()
	local delay = 1		-- delaying first refresh by x seconds
	debug("initstatus("..lul_device..") startup for Root device, delay:"..delay)
	luup.call_delay("startupDeferred", delay, tostring(lul_device))		
end
 
-- do not delete, last line must be a CR according to MCV wiki page
