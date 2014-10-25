#!/usr/bin/lua
local version = "2.1"
local cfg = require("config")
local socket = require("socket")
local dc = socket.tcp()
dc:settimeout(1)
local commands = {} -- таблица, в которой будут храниться команды (сообщения) от хаба
local timeout = cfg.timeout or 180
local timestamp = cfg.timestamp or "[%d-%m-%Y %H:%M:%S]"
local die_command
if cfg.control_nick and cfg.control_nick ~= "" then
	die_command = ("$To: %s From: %s $<%s> !die"):format(cfg.nick, cfg.control_nick, cfg.control_nick)
end
local http, url
if cfg.logger then
	http = require("socket.http")
	url = require("socket.url")
end

local function show(text, ...)
	print(("%s %s"):format(os.date(timestamp), text:format(...)))
end

local show_info_msg = cfg.hide_info_msg and function () end or show
-- подменяем вывод служебных сообщений пустой функцией

local function show_chat_msg(user, message, me) -- me = 0 или 1
	if not cfg.ignore or not cfg.ignore[user] then
		message = message:gsub("&#36;", "$")
		message = message:gsub("&#124;", "|")
		if not cfg.hide_chat_msg then
			show(me == 1 and "* %s %s" or "<%s> %s", user, message)
		end
		if cfg.logger then
			local time = os.time()
			for logger_url, token in pairs(cfg.logger) do
				local post = ("time=%s&user=%s&message=%s&me=%s&token=%s"):format(time, url.escape(user), url.escape(message), me, url.escape(token))
				http.request(logger_url, post)
			end
		end
	end
end

local function die(dietext, ...)
	show_info_msg(dietext, ...)
	dc:close()
	os.exit(1)
end

local function receive()
	-- возвращает команды (сообщения) хаба по одной (без конечного '|')
	-- хранит их в таблице commands, когда она пустеет - читает из сокета
	-- данные в свой буфер кусками, пока не встретит в конце куска '|',
	-- потом сплитит буфер в таблицу
	if next(commands) == nil then
		local fail = true -- флаг для выхода цикла
		local count = 0 -- счётчик подряд идущих пустых данных/таймаутов
		local buffer = ""
		while count < timeout do
			local fulldata, status, partdata = dc:receive("*a")
			-- status = closed или timeout при соответствующих ошибках
			local data = fulldata or partdata
			if status == "closed" then die("Socket closed") end
			if data ~= "" then
				buffer = buffer .. data
				if data:sub(-1) == "|" and buffer:len() > 1 then
					fail = false
					break
				end
			else
				count = count + 1
			end
		end
		if fail then
			die("Timeout (%s s)", timeout)
		else
			buffer:gsub("([^|]+)|", function (c) table.insert(commands, c) end) -- split
		end
	end
	return table.remove(commands, 1)
end

local function lock2key(lock)
	local function bitwise(x, y, bw)
		local c, p = 0, 1
		local function odd(x) return x % 2 ~= 0 end
		local op = {
			["xor"] = function(x, y) return (odd(x) and not odd(y)) or (odd(y) and not odd(x)) end,
			["and"] = function(x, y) return odd(x) and odd(y) end,
			["or"] = function(x, y) return odd(x) or odd(y) end
		}
		while x > 0 or y > 0 do
			if op[bw](x, y) then c = c + p end
			x = math.floor(x / 2)
			y = math.floor(y / 2)
			p = p * 2
		end
		return c
	end
	local key = {}
	table.insert(key, bitwise(bitwise(bitwise(lock:byte(1), lock:byte(-1), "xor"), lock:byte(-2), "xor"), 5, "xor"))
	for i = 2, #lock do
		table.insert(key, bitwise(lock:byte(i-1), lock:byte(i), "xor"))
	end
	local function nibbleswap(bits)
		return bitwise(bitwise(bits*16, 240, "and"), bitwise(math.floor(bits/16), 15, "and"), "or")
	end
	local escape = {[0] = true, [5] = true, [36] = true, [96] = true, [124] = true, [126] = true}
	for i = 1, #key do
		local b = nibbleswap(key[i])
		key[i] = escape[b] and string.format("/%%DCN%03d%%/", b) or string.char(b)
	end
	return table.concat(key)
end

show_info_msg("lunadc v%s", version)
local success, errormessage = dc:connect(cfg.host, cfg.port)
-- success = nil при ошибке, 1 при успешном выполнении
if not success then die("Socket error: %s", errormessage) end

local data = receive() -- $Lock
local lock = data:match("^$Lock (.+) Pk=.+")
if not lock then die("$Lock is not received") end
local key = lock2key(lock)
local supports = lock:find("EXTENDEDPROTOCOL") and "$Supports HubTopic|" or ""
dc:send(("%s$Key %s|$ValidateNick %s|"):format(supports, key, cfg.nick))

local hello_received = false
local tries = 10 -- делаем несколько попыток получить $Hello
while tries do
	local data = receive()
	local hubname = data:match("$HubName (.+)")
	if hubname then
		show_info_msg("Hub: %s", hubname)
	elseif data:sub(1,1) ~= "$" then
		show_info_msg(data) -- сообщения ботов, хаба, etc.
	elseif data:find("$Hello") then
		hello_received = true
		show_info_msg("Hello, %s", cfg.nick)
		break
	elseif data == "$GetPass" then
		if cfg.pass and cfg.pass ~= "" then
			dc:send(("$MyPass %s|"):format(cfg.pass))
			show_info_msg("Password has been sent")
		else
			die("Password has been requested but not specified")
		end
	elseif data == "$BadPass" then
		die("Wrong password")
	elseif data:find("$Supports") then
		-- pass
	else
		tries = tries - 1
	end
end
if not hello_received then die("$Hello is not received") end

local slots = cfg.slots or 10
local share = cfg.share or 0
local desc = cfg.desc or "lunadc - standalone Direct Connect bot for chat logging"
local email = cfg.email or "lunadc@ya.ru"
local tag = ("<lunadc V:%s,M:P,H:0/1/0,S:%s>"):format(version, slots)
dc:send(("$Version 1,0091|$MyINFO $ALL %s %s%s$ $100 $%s$%s$|"):format(cfg.nick, desc, tag, email, share))

while true do
	local data = receive()
	if data == die_command then
		die("Command !die has been received from %s", cfg.control_nick)
	end
	local user, message = data:match("^<([^%c]-)> (.*)")
	local me = 0
	if user then
		if message:sub(1, 3) == "/me" then
			message = message:sub(5)
			me = 1
		end
		show_chat_msg(user, message, me)
	else
		local user, message = data:match("^%*+ ?([^%*%c ]+) (.*)")
		-- варианты /me - * ник действие; ** ник действие; *ник действие и т.д.
		if user then
			show_chat_msg(user, message, 1)
		end
	end
end
