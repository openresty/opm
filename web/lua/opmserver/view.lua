local _M = {}

local templates = require "opmserver.templates"
local get_current_user
local say = ngx.say

function _M.show(tpl_name, context)
    if not get_current_user then
        get_current_user = require "opmserver".get_current_user
    end

    context = context or {}

    local curr_user, err = get_current_user()
    if curr_user then
        context.curr_user = curr_user
    end

    tpl_name = tpl_name .. '.tt2'
    local sub_tpl_html = templates.process(tpl_name, context)
    context.main_html = sub_tpl_html

    local html = templates.process('layout.tt2', context)
    say(html)
end

return _M
