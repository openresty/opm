local _M = {}


local json_encode = require "cjson.safe" .encode
local json_decode = require("cjson.safe").decode
local resty_random = require("resty.random")
local str = require("resty.string")
local random_bytes = resty_random.bytes
local to_hex = str.to_hex


local ngx = ngx
local ngx_exit = ngx.exit
local read_body = ngx.req.read_body
local get_body_data = ngx.req.get_body_data
local re_find = ngx.re.find
local re_gsub = ngx.re.gsub
local io_open = io.open
local type = type


local HTML_ENTITIES = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
}

local CODE_ENTITIES = {
    ["{"] = "&#123;",
    ["}"] = "&#125;",
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&#39;",
}


function _M.to_html(s, c)
    if type(s) == "string" then
        if c then
            s = re_gsub(s, "[}{\"><'&]", CODE_ENTITIES, "jo")
        else
            s = re_gsub(s, "[\"><'&]", HTML_ENTITIES, "jo")
        end
    end

    return s
end


function _M.read_file(path)
    local fp, err = io_open(path)
    if not fp then
        return nil, err
    end

    local chunk = fp:read("*all")
    fp:close()

    return chunk
end


function _M.gen_random_string(length)
    length = length or 32
    length = length / 2
    local r = random_bytes(length, true)

    return to_hex(r)
end


local function remove_null(t)
    for k, v in pairs(t) do
        if type(v) == "userdata" then
            t[k] = nil
        end

        if type(v) == "table" then
            remove_null(v)
        end
    end
    return t
end


function _M.get_post_args(explicit)
    read_body()

    local data = get_body_data()

    if not data and explicit then
        return ngx_exit(400)
    end

    if not data then
        return {}
    end

    if data and #data > 0 then
        local res, err = json_decode(data)
        if not res then
            return nil, "invalid json"
        end
        return remove_null(res)
    end

    return nil
end


local function _output(res)
    local data = json_encode(res)

    ngx.status = 200
    ngx.say(data)
    ngx.exit(200)
end


function _M.exit_ok(data)
    return _output({ status = 0, data = data })
end


function _M.exit_err(msg)
    return _output({ status = 1, msg = msg })
end


function _M.shell_escape(s, quote)
    local typ = type(s)
    if typ == "string" then
        if re_find(s, [=[[^a-zA-Z0-9._+:@%/-]]=]) then
            s = re_gsub(s, [[\\]], [[\\\\]], 'jo')
            s = re_gsub(s, [=[[ {}\[\]\(\)"'`#&,;<>\?\$\^\|!~]]=], [[\$0]], 'jo')
        end
    end

    if quote then
        s = quote .. s .. quote
    end

    return s
end


return _M
