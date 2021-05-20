local _M = {}


local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local require = require


function _M.init()
    local process = require "ngx.process"
    local ok, err = process.enable_privileged_agent()
    if not ok then
        ngx_log(ngx_ERR, "enables privileged agent failed error:", err)
    end
end


function _M.init_worker(mode)
    if mode and mode == 'ci' then
        return
    end

    local process = require "ngx.process"
    if process.type() == 'privileged agent' then
        require("opmserver.crontab").init_worker()
    end
end


return _M
