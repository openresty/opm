
local _M = {}
local mt = { __index = _M }

local str_find = string.find
local str_gsub = string.gsub
local abs = math.abs

function _M:new(url, total, page_size, page)

    total = total or 1
    page_size = page_size or 20
    page = page or 1

    local this = {
        total = total,
        page_size = page_size,
        page = page,
        page_count = math.ceil(total / page_size),
        url = url
    }
    
    setmetatable(this, mt)

    return this
end

function _M:setUrl(page)

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

function _M:first(name)

    name = name or 'first'
    if self.page > 1 then
        
        return '<a href="' .. self:setUrl(1) .. '">' .. name .. '</a>'
    else
        return ''
    end
end

function _M:prev()

    local page
    if self.page == 1 then
        page = 1
    else 
        page = self.page - 1
    end
    if self.page > 1 then
        
        return '<a href="' .. self:setUrl(page) .. '">prev</a>'
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
            
            return '<a href="' .. self:setUrl(pages) .. '">next</a>'
        else 
            
            return '<a href="' .. self:setUrl(page) .. '">next</a>'
        end
    else 
        
        return "<span class='disabled'>next</span>"
    end
end

function _M:last(name)

    name = name or 'last'
    if self.page < self.page_count then
        
        return '<a href="' .. self:setUrl(self.page_count) .. '">' 
            .. name .. '</a>'
    else
        return ''
    end
end

function _M:slide()

    local ret = ''
    local i = 1

    while i <= self.page_count do
        local show_link
        if i == self.page then
            ret = ret .. ' <span class="current">' .. i .. '</span>'
        else
            if i == 1 or i == self.page_count or abs(i - self.page) < 3 then
                show_link = true
            elseif abs(i - self.page) == 3 then
                if (i == 2 and self.page == 5) or 
                    (i == self.page_count - 1 and self.page == self.page_count - 4) then
                    show_link = true
                else
                    ret = ret .. " ... "
                end
            end
        end

        if show_link then
            ret = ret .. ' <a href="' .. self:setUrl(i) .. '">' 
                .. i .. '</a>'
        end

        i = i + 1
    end

    return ret
end

function _M:show()

    local ret = '<div class="pager">'

    ret = ret .. ' ' .. self:prev()
    ret = ret .. ' ' .. self:slide()
    ret = ret .. ' ' .. self:next()
    ret = ret .. '</div>'

    return ret
end

function _M.paging(total_count, page_size, curr_page)

    total_count = total_count or 0
    curr_page = curr_page or 1
    page_size = page_size or 20

    local page_count, remainder = math.modf(total_count / page_size)
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

