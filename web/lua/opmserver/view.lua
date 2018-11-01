local _M = {}

local templates = require "opmserver.templates"

local say = ngx.say

function _M.show(tpl_name, context)
    context = context or {}
    tpl_name = tpl_name .. '.tt2'
    local sub_tpl_html = templates.process(tpl_name, context)
    context.main_html = sub_tpl_html

    local html = templates.process('layout.tt2', context)
    say(html)
end

return _M
