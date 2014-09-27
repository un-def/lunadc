#!/usr/bin/lua
version = "2.0"

function show(text, ...) -- ... = таблица arg
	print(("%s %s"):format(os.date(timestamp), text:format(unpack(arg))))
end

show_info_msg = show -- sort of alias (см. проверку cfg.hide_info_msg)

function die(dietext, ...)
	show_info_msg(dietext, unpack(arg))
	tcp:close()
	os.exit(1)
end

function urlencode(str)
	return str:gsub("([^%w%-%_%.%~])", function (c) return ("%%%02X"):format(c:byte()) end)
end

function receive()
	-- возвращает команды (сообщения) хаба по одной (без конечного '|')
	-- хранит их в таблице commands, когда она пустеет - читает из сокета
	-- данные в свой буфер кусками, пока не встретит в конце куска '|',
	-- потом сплитит буфер в таблицу
	if next(commands) == nil then
		local fail = true -- флаг для выхода цикла
		local count = 0 -- счётчик подряд идущих пустых данных/таймаутов
		local buffer = ""
		while count < timeout do
			local fulldata, status, partdata = tcp:receive("*a")
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
			die("Timeout")
		else
			buffer:gsub("([^|]+)|", function (c) table.insert(commands, c) end) -- split
		end
	end
	return table.remove(commands, 1)
end

function show_chat_msg(user, message, me) -- me = 0 или 1
	if not cfg.ignore or not cfg.ignore[user] then
		message = message:gsub("&#36;", "$")
		message = message:gsub("&#124;", "|")
		if not cfg.hide_chat_msg then
			show(me == 1 and "* %s %s" or "<%s> %s", user, message)
		end
		if cfg.logger then
			for logger_url, token in pairs(cfg.logger) do
				local post = ("time=%s&user=%s&message=%s&me=%s&token=%s"):format(os.time(), urlencode(user), urlencode(message), me, token)
				http.request(logger_url, post)
			end
		end
	end
end

function lock2key(lock)
	local function bitwise(x, y, bw)
		local c, p = 0, 1
		local function bODD(x)
			return x ~= math.floor(x / 2) * 2
		end
		while x > 0 or y > 0 do
			if bw == "xor" then
				if (bODD(x) and not bODD(y)) or (bODD(y) and not bODD(x)) then
					c = c + p
				end
			elseif bw == "and" then
				if bODD(x) and bODD(y) then
					c = c + p
				end
			elseif bw == "or" then
				if bODD(x) or bODD(y) then
					c = c + p
				end
			end
			x = math.floor(x / 2)
			y = math.floor(y / 2)
			p = p * 2
		end
		return c
	end
	local key = {}
	table.insert(key, bitwise(bitwise(bitwise(string.byte(lock, 1), string.byte(lock, -1), "xor"), string.byte(lock, -2), "xor"), 5, "xor"))
	for i = 2, string.len(lock), 1 do
		table.insert(key, bitwise(string.byte(lock, i), string.byte(lock, i - 1), "xor"))
	end
	local function nibbleswap(bits)
		return bitwise(bitwise(bits * (2 ^ 4), 240, "and"), bitwise(math.floor(bits / (2 ^ 4)), 15, "and"), "or")
	end
	local g = {["5"] = 1, ["0"] = 1, ["36"] = 1, ["96"] = 1, ["124"] = 1, ["126"] = 1}
	for i = 1, #key do
		local b = nibbleswap(rawget(key, i))
		rawset(key, i, (g[tostring(b)] and
		string.format("/%%DCN%03d%%/", b) or string.char(b)))
	end
	return table.concat(key)
end
-------------------------------------------------------
cfg = require("config")
socket = require("socket")
tcp = socket.tcp()
tcp:settimeout(1)
timeout = cfg.timeout or 180
commands = {} -- таблица, в которой будут храниться команды (сообщения) от хаба
if cfg.hide_info_msg then
	show_info_msg = function () end
	-- подменяем вывод служебных сообщений пустой функцией
end
timestamp = cfg.timestamp or "[%d-%m-%Y %H:%M:%S]"

show_info_msg("lunadc v%s", version)

success, errormessage = tcp:connect(cfg.host, cfg.port)
-- success = nil при ошибке, 1 при успешном выполнении
if not success then die("Socket error: %s", errormessage) end

data = receive() -- $Lock
lock = data:match("^$Lock (.+) Pk=.+")
if not lock then die("$Lock is not received") end

key = lock2key(lock)
supports = lock:find("EXTENDEDPROTOCOL") and "$Supports HubTopic|" or ""
tcp:send(("%s$Key %s|$ValidateNick %s|"):format(supports, key, cfg.nick))

hello_received = false
tries = 10 -- делаем несколько попыток получить $Hello
while tries do
	data = receive()
	hubname = data:match("$HubName (.+)")
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
			tcp:send(("$MyPass %s|"):format(cfg.pass))
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

slots = cfg.slots or 10
share = cfg.share or 0
desc = cfg.desc or "lunadc - standalone Direct Connect bot for chat logging"
email = cfg.email or "lunadc@ya.ru"

tag = ("<lunadc V:%s,M:P,H:0/1/0,S:%s>"):format(version, slots)
tcp:send(("$Version 1,0091|$MyINFO $ALL %s %s%s$ $100 $%s$%s$|"):format(cfg.nick, desc, tag, email, share))

if cfg.logger then http = require("socket.http") end

while true do
	data = receive()
	user, message = data:match("^<([^%c]-)> (.*)")
	if user then
		if message:sub(1, 3) == "/me" then
			message = message:sub(5)
			me = 1
		else
			me = 0
		end
		show_chat_msg(user, message, me)
	else
		user, message = data:match("^%*+ ?([^%*%c ]+) (.*)")
		-- варианты /me - * ник действие; ** ник действие; *ник действие и т.д.
		if user then
			show_chat_msg(user, message, 1)
		end
	end
end
