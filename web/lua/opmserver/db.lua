local pgmoon = require "pgmoon"
local db_conf = require("opmserver.conf").load_entry("db")

local ngx = ngx
local null = ngx.null
local set_quote_sql_str = ndk.set_var.set_quote_pgsql_str

local _M = {}

local idle_timeout = (db_conf.max_idle_timeout or 60) * 1000
local pool_size = db_conf.pool_size or 5


function _M.quote(v)
    if not v or v == null then
        return "null"
    end
    local typ = type(v)
    if typ == "number" or typ == "boolean" then
        return tostring(v)
    end
    return set_quote_sql_str(v)
end


function _M.query(sql)
    local pg = pgmoon.new(db_conf)

    local ok, err = pg:connect()
    if not ok then
        return nil, ("failed to connect pg: " .. err or "")
    end

    local result, err, partial, num_queries = pg:query(sql)
    if not result and err then
        ngx.log(ngx.ERR, "failed to query sql, err: ", err, ", sql: ", sql)
        pg:disconnect()
        return nil, err
    end

    local ok, err = pg:keepalive(idle_timeout, pool_size)
    if not ok then
        ngx.log(ngx.ERR, "pg keepalive failed: ", err)
    end

    return result, nil, partial, num_queries
end


return _M
