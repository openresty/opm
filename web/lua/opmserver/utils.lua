
local _M = {}

local ngx = ngx
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


return _M
