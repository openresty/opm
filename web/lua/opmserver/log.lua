local _M = {}

local cur_level = ngx.config.subsystem == "http" and
                  require "ngx.errlog" .get_sys_filter_level()
local ngx_log = ngx.log
local ngx_CRIT = ngx.CRIT
local ngx_ERR = ngx.ERR
local ngx_WARN = ngx.WARN
local ngx_INFO = ngx.INFO
local ngx_NOTICE = ngx.NOTICE
local ngx_DEBUG = ngx.DEBUG
local DEBUG = ngx.config.debug


-- NGX_LOG_STDERR            0
-- NGX_LOG_EMERG             1
-- NGX_LOG_ALERT             2
-- NGX_LOG_CRIT              3
-- NGX_LOG_ERR               4
-- NGX_LOG_WARN              5
-- NGX_LOG_NOTICE            6
-- NGX_LOG_INFO              7
-- NGX_LOG_DEBUG             8


function _M.crit(...)
    if cur_level and ngx_CRIT > cur_level then
        return
    end

    return ngx_log(ngx_CRIT, ...)
end


function _M.error(...)
    if cur_level and  ngx_ERR > cur_level then
        return
    end

    return ngx_log(ngx_ERR, ...)
end


function _M.warn(...)
    if cur_level and ngx_WARN > cur_level then
        return
    end

    return ngx_log(ngx_WARN, ...)
end


function _M.notice(...)
    if cur_level and ngx_NOTICE > cur_level then
        return
    end

    return ngx_log(ngx_NOTICE, ...)
end


function _M.info(...)
    if cur_level and ngx_INFO > cur_level then
        return
    end

    return ngx_log(ngx_INFO, ...)
end


function _M.debug(...)
    if not DEBUG and cur_level and ngx_DEBUG > cur_level then
        return
    end

    return ngx_log(ngx_DEBUG, ...)
end


return _M
