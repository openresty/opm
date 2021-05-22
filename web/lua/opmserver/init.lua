local _M = {}


local log = require("opmserver.log")


local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local require = require


local function init_random()
    local frandom, err = io.open("/dev/urandom", "rb")
    if not frandom then
        log.crit("failed to open file /dev/urandom: ", err)

        math.randomseed(ngx.now())

    else
        local str = frandom:read(4)
        frandom:close()
        local seed = 0
        for i = 1, 4 do
            seed = bit.bor(bit.lshift(seed, 8), str:byte(i))
        end
        seed = bit.bxor(seed, ngx.worker.pid())
        math.randomseed(seed)
    end
end


function _M.init()
    init_random()

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
