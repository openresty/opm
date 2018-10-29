
local _M = {}
local mt = { __index = _M }

local str_find = string.find
local str_gsub = string.gsub
local tab_concat = table.concat
local abs = math.abs
local modf = math.modf
local ceil = math.ceil

local function tab_append(t, v, idx)
    idx = idx or #t
    idx = idx + 1
    t[idx] = v

    return idx
end

function _M:new(url, total, page_size, page)

    total = total or 1
    page_size = page_size or 20
    page = page or 1

    local this = {
        total = total,
        page_size = page_size,
        page = page,
        page_count = ceil(total / page_size),
        url = url
    }
    
    setmetatable(this, mt)

    return this
end

function _M:set_url(page)

    local url = self.url

    if str_find(url, '[&%?]page=') then
        url = str_gsub(url, '([&%?])page=%d+', '%1page=' .. page)

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

    local page

    if self.page == 1 then
        page = 1
    
    else 
        page = self.page - 1
    end

    if self.page > 1 then
        return '<a href="' .. self:set_url(page) .. '">prev</a>'

    else 
        return "<span class='disabled'>prev</span>"
    end

end

function _M:next()

    local pages
    local page = self.page + 1

    if self.page < self.page_count then
        if self.page == 1 then
            pages = self.page + 1
            return '<a href="' .. self:set_url(pages) .. '">next</a>'
        
        else 
            return '<a href="' .. self:set_url(page) .. '">next</a>'
        end

    else 
        return "<span class='disabled'>next</span>"
    end

end

function _M:slide()

    local ret = {}
    local tlen = 0
    local i = 1

    while i <= self.page_count do
        local show_link

        if i == self.page then
            tlen = tab_append(ret, ' <span class="current">' .. i .. '</span>', tlen)

        else
            if i == 1 or i == self.page_count or abs(i - self.page) < 3 then
                show_link = true
            
            elseif abs(i - self.page) == 3 then
                if (i == 2 and self.page == 5) or 
                    (i == self.page_count - 1 and 
                    self.page == self.page_count - 4) then

                    show_link = true
                
                else
                    tlen = tab_append(ret, " ... ", tlen)
                end
            end
        end

        if show_link then
            tlen = tab_append(ret, '<a href="' .. self:set_url(i) .. '">' 
                    .. i .. '</a>', tlen)
        end

        i = i + 1
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

