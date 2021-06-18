local _M = {}

local resty_ini = require "resty.ini"

local config
local prefix = ngx.config.prefix()

do
    config = assert(resty_ini.parse_file(prefix .. "conf/config.ini"))
end


function _M.load_entry(key)
    return config[key]
end


function _M.get_config()
    return config
end


return _M
