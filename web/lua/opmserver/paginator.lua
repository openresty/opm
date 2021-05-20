local _M = {}
local mt = { __index = _M }

local select = select
local setmetatable = setmetatable
local str_find = string.find
local str_gsub = string.gsub
local tab_concat = table.concat
local modf = math.modf
local ceil = math.ceil

local function tab_append(t, idx, ...)
    local n = select("#", ...)
    for i = 1, n do
        t[idx + i] = select(i, ...)
    end
    return idx + n
end

function _M:new(url, total, page_size, page)
    total = total or 1
    page_size = page_size or 20

    page = page or 1
    if page < 1 then
        page = 1
    end

    local page_count = ceil(total / page_size)
    if page > page_count then
        page = page_count
    end

    local this = {
        total = total,
        page_size = page_size,
        page = page,
        page_count = page_count,
        url = url
    }

    setmetatable(this, mt)

    return this
end

function _M:set_url(page)
    local url = self.url

    if str_find(url, '[&%?]page=') then
        url = str_gsub(url, '([&%?])page=[^&#]*', '%1page=' .. page)

    else
        if not str_find(url, '%?') then
            url = url .. '?'
        end

        if str_find(url, '%w=') then
            url = url .. '&'
        end

        url = url .. 'page=' .. page
    end

    return url
end

function _M:prev()
    if self.page == 1 then
        return "<span class='disabled'>prev</span>"
    end

    return '<a href="' .. self:set_url(self.page - 1) .. '">prev</a>'
end

function _M:next()
    if self.page < self.page_count then
        return '<a href="' .. self:set_url(self.page + 1) .. '">next</a>'
    end

    return "<span class='disabled'>next</span>"
end

function _M:url_range(list, tlen, first, last)
    last = last or first

    for i = first, last do
        if i == self.page then
            tlen = tab_append(list, tlen, ' <span class="current">', 
                              i, '</span>')

        else
            tlen = tab_append(list, tlen, '<a href="', self:set_url(i), '">', 
                              i, '</a>')
        end
    end

    return tlen
end

function _M:slide(each_side)
    local ret = {}
    local tlen = 0

    each_side = each_side or 2
    local window = each_side * 2
    local left_dot_end
    local right_dot_begin

    if self.page > each_side + 3 then
        left_dot_end = self.page - each_side
        if left_dot_end > self.page_count - window then
            left_dot_end = self.page_count - window
        end
        if left_dot_end <= 3 then
            left_dot_end = nil
        end
    end

    if self.page <= self.page_count - (each_side + 3) 
       and self.page_count > (each_side + 3)
    then
        right_dot_begin = self.page + each_side
        if right_dot_begin <= window then
            right_dot_begin = window + 1
        end
        if self.page_count - right_dot_begin <= 2 then
            right_dot_begin = nil
        end
    end

    if left_dot_end then
        tlen = self:url_range(ret, tlen, 1)
        tlen = tab_append(ret, tlen, " ... ")
        if right_dot_begin then
            tlen = self:url_range(ret, tlen, left_dot_end, right_dot_begin)
            tlen = tab_append(ret, tlen, " ... ")
            tlen = self:url_range(ret, tlen, self.page_count)

        else
            tlen = self:url_range(ret, tlen, left_dot_end, self.page_count)
        end

    else
        if right_dot_begin then
            tlen = self:url_range(ret, tlen, 1, right_dot_begin)
            tlen = tab_append(ret, tlen, " ... ")
            tlen = self:url_range(ret, tlen, self.page_count)

        else
            tlen = self:url_range(ret, tlen, 1, self.page_count)
        end
    end

    return tab_concat(ret)
end

function _M:show()
    local ret = '<div class="pager">'
                .. ' ' .. self:prev()
                .. ' ' .. self:slide()
                .. ' ' .. self:next()
                ..      '</div>'

    return ret
end

function _M.paging(total_count, page_size, curr_page)
    total_count = total_count or 0
    curr_page = curr_page or 1
    if curr_page < 1 then
        curr_page = 1
    end
    page_size = page_size or 20

    local page_count, remainder = modf(total_count / page_size)
    if remainder > 0 then
        page_count = page_count + 1 
    end
    if curr_page > page_count then
        curr_page = page_count
    end

    local offset = (curr_page - 1) * page_size

    local limit = page_size
    if limit > total_count then
        limit = total_count
    end

    return limit, offset
end

return _M
