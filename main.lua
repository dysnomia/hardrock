-- dispatcher for hardrock clients
-- provides functions: 
--   log(...), printf(...), 
--   jrecv() -> get json message, jsend(tbl) -> send 'tbl' as json message
--   action(typ) -> send player action to server
-- provides global variables:
--   player, character, cartype identifying the player

require "strict"
local socket = require "socket"
local json = require "dkjson"

-- connection constants
local host = '127.0.0.1'
local port = 1993

-- player constants -> global
player = "wadehn"
character = "Rip"
cartype = "Marauder"

-- enable debug messages?
local NDEBUG = false

if rawget(_G, "arg") then
	host = arg[1] or host
	player = arg[2] or player
	character = arg[3] or character
	cartype = arg[4] or cartype
end

-- print stuff if debug mode enabled
function log(...)
	if NDEBUG then
		print(...)
	end
end

-- print with formatting
function printf(...)
	io.write(string.format(...))
end

-- print json messages if debug mode activated
local function dbg_msg(str)
	if NDEBUG then
		log(json.encode(json.decode(str), {indent = true}) .. "\n")
	end
	return str
end

-- create connection to server
local conn = assert(socket.connect(host, port))

-- send json-encoding of 'table'
function jsend(table)
	local str = json.encode(table) .. "\n"
	local last_send = 1
	while last_send < #str do
		last_send = assert(conn:send(str, last_send))
	end
end

-- get decoding of json message
function jrecv()
	return json.decode(dbg_msg(assert(conn:receive("*l"))))
end

-- send player action to server
function action(typ)
	jsend({message = "action", ["type"] = typ})
end

-- handshake
local handshake = {
	message = "connect",
	["type"] = "player",
	name = player,
	character = character,
	cartype = cartype,
	tracktiled = true
}
log("Sending handshake as player '" .. handshake.name .. "' ...\n")
jsend(handshake)
local resp = jrecv()
if resp.message ~= "connect" or resp.status ~= true then
	error("Handshake unsucessful...")
end

-- our client
local client = require "visibility_client"
--local client = require "accelerate_client"

-- dispatch messages to client
local function dispatch(client)
	while true do
		local req = jrecv()
		if client[req.message] then
			client[req.message](req)
			if (req.message == "raceover") then
				--log("End of race\n")
			end
		end
	end
end

dispatch(client)
conn:close()