local resty_ini = require "resty.ini"


local ngx = ngx
local find = ngx.re.find
local gsub = ngx.re.gsub
local sub = string.sub
local tostring = tostring
local tonumber = tonumber
local encode_base64 = ngx.encode_base64
local socket_tcp = ngx.socket.tcp


local account, password, sender_addr
local sender_name = "OPM Indexer"


local _M = {
}


local function send_cmd(sock, cmd)
    if not account then
        local ini_file = ngx.config.prefix() .. "email.ini"

        local conf, err = resty_ini.parse_file(ini_file)
        if not conf then
            return nil, ini_file .. ": failed to load ini file: " .. err
        end

        local default = conf.default

        account = default.account
        if not account or account == "" then
            return nil, ini_file .. ": key \"account\" not found"
        end

        -- ngx.log(ngx.WARN, "account: ", account)

        password = default.password
        if not password or password == "" then
            return nil, ini_file .. ": key \"password\" not found"
        end

        -- ngx.log(ngx.WARN, "password: ", password)

        sender_addr = default.sender_addr
        if not sender_addr or sender_addr == "" then
            return nil, ini_file .. ": key \"sender_addr\" not found"
        end
    end

    -- ngx.log(ngx.WARN, "> ", cmd)

    local bytes, err = sock:send(cmd .. "\r\n")
    if not bytes then
        return bytes, err
    end

    do
        local lines = {}
        local i = 0
        local line, err = sock:receive()
        if not line then
            return nil, err
        end

        while true do
            local fr, to, err = find(line, [[^(\d+)-]], "jo", nil, 1)
            if err then
                return nil, "failed to call ngx.re.find: " .. tostring(err)
            end
            if not fr then
                break
            end
            local status = tonumber(sub(line, fr, to))
            if status >= 400 then
                return nil, line
            end
            i = i + 1
            lines[i] = line
            local err
            line, err = sock:receive()
            if not line then
                return nil, err
            end
        end

        local fr, to, err = find(line, [[^(\d+) ]], "jo", nil, 1)
        if err then
            return nil, "failed to call ngx.re.find: " .. tostring(err)
        end
        if not fr then
            return nil, "syntax error: " .. tostring(line)
        end
        local status = tonumber(sub(line, fr, to))
        if status >= 400 then
            return nil, line
        end

        i = i + 1
        lines[i] = line
        -- ngx.log(ngx.WARN, table.concat(lines, "\n"))
    end

    return true
end


function _M.send_mail(recipient, recipient_name, mail_title, mail_body)
    local sock = socket_tcp()
    local host = "smtp.mailgun.org"

    local ok, err = sock:connect(host, 587)
    if not ok then
        return nil, "failed to connect to " .. (host or "") .. ":587: "
                    .. (err or "")
    end

    local line, err = sock:receive()
    if not line then
        return nil, "failed to receive the first line from "
                    .. (host or "") .. ":587: " .. (err or "")
    end
    -- ngx.log(ngx.WARN, line)

    ok, err = send_cmd(sock, "EHLO " .. host)
    if not ok then
        return nil, err
    end

    ok, err = send_cmd(sock, "STARTTLS")
    if not ok then
        return nil, err
    end

    local sess, err = sock:sslhandshake(nil, host, true)
    if not sess then
        return nil, err
    end

    ok, err = send_cmd(sock, "EHLO " .. host)
    if not ok then
        return nil, err
    end

    local auth = encode_base64("\0" .. account .. "\0" .. password)

    ok, err = send_cmd(sock, "AUTH PLAIN " .. auth)
    if not ok then
        return nil, err
    end

    local ok, err = send_cmd(sock, "MAIL FROM:<" .. sender_addr .. ">")
    if not ok then
        return nil, err
    end

    local ok, err = send_cmd(sock, "RCPT TO:<" .. recipient .. ">")
    if not ok then
        return nil, err
    end

    local bytes, err = sock:send{
        "DATA\r\n",
        "FROM: ", sender_name, " <", sender_addr, ">\r\n",
        "Subject: ", mail_title, "\r\n",
        "To: ", recipient_name, " <", recipient, ">\r\n",
        "Content-Transfer-Encoding: base64\r\n",
        "Content-Type: text/plain; charset=utf-8\r\n\r\n",
        encode_base64(mail_body), "\n",
    }
    if not bytes then
        return nil, err
    end

    ok, err = send_cmd(sock, "\r\n.")
    if not ok then
        return nil, err
    end

    ok, err = send_cmd(sock, "QUIT")
    if not ok then
        return nil, err
    end

    ok, err = sock:close()
    if not ok then
        return nil, err
    end

    return true
end


return _M
