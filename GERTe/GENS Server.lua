--Assuming Lua Socket availability

--For quick reference for communication purposes:
--Follows similar standard to HTTP
--GENS %vers%\r\n
--%dest% %origin%\r\n\r\n

--GENS %vers%\r\n
--FOUND: %ip%\r\n OR ERR: %err%\r\n

--Warning: Designed in Lua 5.1 for compatibilty with LuaForWindows (Developer's Version)

startTime = os.time()

logFile = io.open("log.txt", "a")
if not logFile then
	logFile = io.open("log.txt", "w")
end

logFile:write("[" .. startTime .. "] -----     Initializing      -----\n")
print("[" .. startTime .. "] -----     Initializing      -----")

function log(str)
	formatted = "[" .. os.time() .. "] " .. str .. "\n"
	logFile:write(formatted)
	logFile:flush()
	io.stdout:write(formatted)
end

socket = require "socket"
ipSeg = "%d?%d?%d"
ipPat = ipSeg .. "%." .. ipSeg .. "%." .. ipSeg .. "%." .. ipSeg
ipSeg = nil
gertPat = "%d%d%d%-%d%d%d%d"
fullPat = gertPat .. "%-%d%d%d%d"

vers = "0.0"
compatible = {}
compatible[vers] = true

function lookup(id)
	return database[string.match(id, "(" .. gertPat .. ")%-%d%d%d%d")] or nil
end

function error(str)
	return log("[E] " .. str)
end

function warn(str)
	return log("[W] ".. str)
end

function info(str)
	return log("[I] " .. str)
end

function send(data, sock)
	if ({sock:receive(0)})[2] == "closed" then
		return warn("Socket closed unexpectantly")
	end
	local str = "GENS " .. vers .. "\r\n"
	for k, line in ipairs(data) do
		str = str .. line .. "\r\n"
	end
	sock:send(str .. "\r\n") --Optimized, works around Nagel's without disabling it
	sock:close()
end

function main()
	local client = serv:accept() --WARNING: Will block, this code won't close cleanly
	local remoteip = ({client:getpeername()})[1]
	if not client then return end --If client isn't waiting then cancel
	client:settimeout(5)
	local header, err = client:receive() --TODO: Implement something like socket.select or something
	if err == "timeout" then
		send({"ERR: TIMEDOUT"}, client)
		return error(remoteip .. " is being a slow loris (timedout)")
	elseif err == "closed" then
		return error(remoteip .. " caused an unexpected close")
	elseif string.sub(header, 1, 4) ~= "GENS" then
		client:send("HTTP/1.1 400 Bad Request\r\n") --Why not? It's universal
		send({"ERR: NOT GENS"}, client)
		return warn("Non-GENS from " .. remoteip)
	elseif not compatible[string.sub(header, 6)] then
		send({"ERR: NOT COMPATIBLE"}, client)
		return warn("Non-compatible GENS from " .. remoteip)
	end
	local request, err = client:receive()
	if err == "timeout" then
		send({"ERR: TIMEOUT"}, client)
		return error(remoteip .. " is being a slow loris (timedout)")
	elseif err == "closed" then
		return error(remoteip .. " caused an unexpected close")
	end
	local reqID, origin = string.match(request, "(" .. fullPat .. ") (" .. fullPat .. ")")
	if not reqID or not origin then
		error(remoteip .. " sent a malformed request")
		return send({"ERR: MALFORMED REQUEST"}, client)
	end
	local tracker = origin .. " (" .. remoteip ..")"
	local map = lookup(reqID)
	if not map then
		send({"ERR: NOT FOUND"}, client)
		return error(tracker .. " attempted to find " .. reqID .. " but failed")
	end
	send({"FOUND: " .. map}, client)
	return info(tracker .. " found " .. reqID .. " (" .. map .. ")")
end

file = io.open("database.txt", "r")

if not file then
	return error("Database file not found.")
end

serv = socket.tcp()
io.stdout:write("[???] Run Server On Port: ")
port = io.read()
serv:bind("*", port)
serv:listen(10)
serv:settimeout(0) --Allows non-blocking calls
log("Server Open on " .. port)
port = nil

log("Building Database")

database = {}

for entry in function() return file:read() end do
	local id, addr = string.match(entry, "(" .. gertPat .. ") = (" .. ipPat .. ")")
	if id and addr then
		database[id] = addr
	end
end

log("-----Initialization Finished-----")

while true do --Primary execution loop
	socket.select({serv}) --Idles much nicer if server isn't ready
	local succ, result = pcall(main)
	if not succ then
		local line, err = string.match(result, ".+:(%d+): (.+)")
		if err == "interrupted!" then
			info("User requested close")
			os.exit(0)
		end
		log("[C] Crashed with error: " .. err .. " on line " .. line)
		log("[C] Report crash please!")
		os.exit(1)
	end
end
