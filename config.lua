local cfg = {}

-- обязательные настройки
cfg.host = "dc.zet"
cfg.port = 411
cfg.nick = "lunadc"

-- дополнительные настройки
cfg.pass = ""
cfg.slots = 3
cfg.share = 4096
cfg.desc = "dev"
cfg.email = "test@test"
cfg.timeout = 900
cfg.ignore = {
	["VerliHub"] = true,
	["MOTD"] = true,
	["Information"] = true
}
cfg.logger = {["http://lunadclogger.dev/api/post"] = "token"}
cfg.hide_info_msg = false
cfg.hide_chat_msg = false
cfg.timestamp = "(%H:%M:%S)"

return cfg
