local _M = {}

local log = require("opmserver.log")
local json_decode = require("cjson.safe").decode
local json_encode = require("cjson.safe").encode
local http = require "resty.http"
local github_oauth = require("opmserver.conf").load_entry("github_oauth")
local common_conf = require("opmserver.conf").load_entry("common")


local ngx = ngx
local ngx_var = ngx.var
local str_find = string.find


local client_id = github_oauth.client_id
local client_secret = github_oauth.client_secret
local env = common_conf.env
local github_oauth_host = github_oauth.host


local function http_request(url, params)
    local httpc = http.new()
    local res, err = httpc:request_uri(url, params)

    if not res then
        return nil, err or 'unknown'
    end

    if res.status ~= 200 and res.status ~= 201 then
        return nil, "response code: " .. res.status .. " body: "
                    .. (res.body or nil)
    end

    log.info("response: ", res.body)

    if not res.body then
        return nil, 'response body is empty'
    end
    local data, err = json_decode(res.body)
    if not data then
        return nil, 'decode response body failed: ' .. err
    end

    return data
end


local function request_access_token(code)
    local url = github_oauth_host .. "/login/oauth/access_token"

    local res, err = http_request(url, {
        method = 'POST',
        headers = {
            ["Accept"] = "application/json",
        },
        query = {
            client_id = client_id,
            client_secret = client_secret,
            code = code,
        },
        ssl_verify = false,
    })

    if not res then
        return nil, err
    end

    return res
end


local function get_user_info(access_token)
    local url = "https://api.github.com/user"

    local res, err = http_request(url, {
        method = 'GET',
        headers = {
            Accept = 'application/vnd.github.v3+json',
            Authorization = 'token ' .. access_token,
        },
        query = {
            access_token = access_token,
        },
        ssl_verify = false,
    })

    return res, err
end


function _M.get_verified_email(access_token)
    local url = "https://api.github.com/user/emails"

    local data, err = http_request(url, {
        method = 'GET',
        headers = {
            Accept = 'application/vnd.github.v3+json',
            Authorization = 'token ' .. access_token,
        },
        query = {
            access_token = access_token,
        },
        ssl_verify = false,
    })

    if not data then
        return nil, 'query user github email info failed: ' .. err
    end

    local email

    for _, item in ipairs(data) do
        if item.primary and item.verified then
            email = item.email
            break
        end
    end

    if not email then
        for _, item in ipairs(data) do
            if item.verified then
                email = item.email
                break
            end
        end
    end

    if not email then
        return nil, "no verified email address found from github: "
                    .. json_encode(data)
    end

    return email
end


function _M.auth(code)
    if not code then
        return nil, "missing code"
    end

    local token_info, err = request_access_token(code)
    if err then
        return nil, 'request access_token failed: ' .. err
    end

    if not token_info or not token_info.access_token then
        return nil, 'get access_token failed'
    end

    log.info('token_info:', json_encode(token_info))

    local scope = token_info.scope
    if not scope or not str_find(scope, "read:org", nil, true) then
        return nil, "personal access token lacking the read:org scope: "
                    .. scope
    end

    local access_token = token_info.access_token
    local user_info, err = get_user_info(access_token)

    if not user_info then
        return nil, "request github user profile failed: " .. err
    end

    log.info("user_info: ", json_encode(user_info))

    return user_info, nil, access_token
end


function _M.get_login_url()
    local state = ""
    local scheme = 'https'
    if env and env == 'dev' then
        scheme = 'http'
    end

    local redirect_url = scheme .. '://' .. ngx_var.http_host .. "/github_auth/"
    local url = "https://github.com/login/oauth/authorize?client_id="
                .. client_id .. "&redirect_uri=" .. redirect_url
                .. "&scope=user:email,read:org&state=" .. state

    return url
end


return _M
