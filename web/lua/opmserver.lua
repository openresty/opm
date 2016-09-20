-- Copyright (C) Yichun Zhang (agentzh)


local DEBUG = false
-- local DEBUG = true


local http = require "resty.http"
local cjson = require "cjson.safe"
local ngx = require "ngx"
local pgmoon = require "pgmoon"
local tab_clear = require "table.clear"


local re_find = ngx.re.find
local re_match = ngx.re.match
local str_find = string.find
local ngx_var = ngx.var
local say = ngx.say
local req_read_body = ngx.req.read_body
local decode_json = cjson.decode
local req_method = ngx.req.get_method
local req_body_file = ngx.req.get_body_file
local os_exec = os.execute
local io_open = io.open
local io_close = io.close
local set_quote_sql_str = ndk.set_var.set_quote_pgsql_str
local assert = assert
local sub = string.sub
local ngx_null = ngx.null
local tab_concat = table.concat


local incoming_directory = "/tmp"
local MIN_TARBALL_SIZE = 136


local _M = {
    version = "0.0.1"
}


local dd
if DEBUG then
    function dd(...)
        ngx.req.discard_body()
        say("DD ", ...)
    end

else
    function dd() end
end


local out_err, log_err, log_and_out_err
local shell, query_db, quote_sql_str
local query_github, query_github_user, query_github_org
local query_github_org_ownership, query_github_user_verified_email
local db_insert_user_info, db_update_user_info
local db_insert_org_info, db_insert_org_ownership
local db_insert_user_verified_email
local match_table = {}
local ver2pg_array


function _M.go()
    local ctx = ngx.ctx

    -- check request method.

    if req_method() ~= "PUT" then
        return ngx.exit(405)
    end

    -- check user-agent.

    local user_agent = ngx_var.http_user_agent
    if not re_find(user_agent, [[^opm \d+\.\d+\.\d+]], "jo") then
        return ngx.exit(405)
    end

    -- check content-length request header.

    -- XXX we do not support chunked encoded request bodies yet.
    local size = tonumber(ngx_var.http_content_length)
    if not size or size < MIN_TARBALL_SIZE then
        return ngx.exit(400)
    end

    -- extract the github account name from the request.

    local account = ngx_var.http_x_account
    ctx.account = account

    if not re_find(account, [[^[-\w]+$]], "jo") then
        return log_and_out_err(ctx, 400, "bad github account name.")
    end

    if re_find(account, [[^luarocks$]], "joi") then
        return log_and_out_err(ctx, 400,
                               "the luarocks account is reserved by opm.")
    end

    dd("account: ", account)

    -- extract the github personal access token from the request.

    local token = ngx_var.http_x_token
    ctx.token = token

    if not re_find(token, [[^[a-f0-9]{40}$]], "ijo") then
        return log_and_out_err(ctx, 400, "bad github personal access token.")
    end

    dd("token: ", token)

    ctx.auth = "token " .. token

    -- extract the uploaded file name from the request.

    local fname = ngx_var.http_x_file

    local m, err = re_match(fname, [[^ ([-\w]+) - ([.\w]+) \.tar\.gz $]],
                            "xjo", nil, match_table)

    if not m then
        assert(not err)
        ngx.status = 400
        out_err("bad uploaded file name.")
        return ngx.exit(400)
    end

    local pkg_name = m[1]
    local pkg_version = m[2]

    if not re_find(pkg_version, [[\d]], "jo") then
        assert(not err)
        ngx.status = 400
        out_err("bad version number in the uploaded file name.")
        return ngx.exit(400)
    end

    -- extract the file checksum.

    local user_md5 = ngx_var.http_x_file_checksum

    if not user_md5
       or not re_find(user_md5, [[ ^ [a-z0-9]{32} $ ]], "jox")
    then
        return log_and_out_err(ctx, 400, "bad user file checksum.")
    end

    -- verify the user github token.

    local sql = "select user_id, login, scopes, verified_email"
                .. " from access_tokens"
                .. " left join users on access_tokens.user_id = users.id"
                .. " where token_hash = crypt("
                .. quote_sql_str(token)
                .. ", token_hash) limit 1"

    -- say(sql)
    local rows = query_db(sql)

    local login, scopes, user_id, verified_email, new_user

    -- say(cjson.encode(rows))
    if #rows == 0 then
        -- say("no token matched in the database")

        local user_info
        user_info, scopes = query_github_user(ctx, token)

        login = user_info.login

        sql = "select id from users where login = "
              .. quote_sql_str(login) .. " limit 1"

        local rows = query_db(sql)

        if #rows == 0 then
            dd("user not found in db.")

            user_id = db_insert_user_info(ctx, user_info)
            -- say("user id: ", user_id)

            new_user = true

        else
            dd("user already in db, updating db record")

            -- say('user info: ', cjson.encode(user_info))

            user_id = assert(rows[1].id)

            db_update_user_info(ctx, user_info, user_id)
        end

        -- save the github token into our database.

        local sql = "insert into access_tokens (user_id, token_hash, scopes)"
                    .. " values(" .. user_id  -- user_id is from database
                    .. ", crypt(" .. quote_sql_str(token)
                    .. ", gen_salt('md5')), " .. quote_sql_str(scopes) .. ")"
        -- say(sql)

        query_db(sql)

    else
        dd("token mached in the database.")

        user_id = assert(rows[1].user_id)
        scopes = assert(rows[1].scopes)
        login = assert(rows[1].login)
        verified_email = rows[1].verified_email
        dd("found verified email from db: ", verified_email)
    end

    local new_org = false
    local org_id

    if login ~= account then
        -- check if the user account is a github org.

        if not scopes or not str_find(scopes, "read:org", nil, true) then
            return log_and_out_err(ctx, 403,
                                   "personal access token lacking ",
                                   "the read:org scope: ", scopes)
        end

        do
            local sql = "select id from orgs where login = "
                        .. quote_sql_str(account)

            local rows = query_db(sql)
            if #rows == 0 then
                dd("no org found in the db.")

                local org_info = query_github_org(ctx, account)

                -- say("org json: ", cjson.encode(org_info))

                org_id = db_insert_org_info(ctx, org_info)

                new_org = true

            else
                dd("found org in the db.")

                org_id = assert(rows[1].id)
            end
        end

        if not new_user then
            -- both user_id and org_id are from our own database.
            local sql = "select id from org_ownership where user_id = "
                        .. user_id .. " and org_id = " .. org_id

            local rows = query_db(sql)

            if #rows == 0 then
                dd("no membership found in the database.")

                query_github_org_ownership(ctx, account, login)
                db_insert_org_ownership(ctx, org_id, user_id)

            else
                dd("found membership in the databse.")
            end

        else
            -- new user

            dd("no membership found in the database.")

            query_github_org_ownership(ctx, account, login)
            db_insert_org_ownership(ctx, org_id, user_id)
        end
    end

    if not verified_email then
        dd("verified email not found, querying github...")
        verified_email = query_github_user_verified_email(ctx)
        db_insert_user_verified_email(ctx, user_id, verified_email)
    end

    local ver_v = ver2pg_array(pkg_version)

    local pkg_id
    do
        local sql = "select id from packages where name = "
                    .. quote_sql_str(pkg_name)

        local rows = query_db(sql)

        if #rows == 0 then
            dd("no package registered in db yet.")

            local sql = "insert into packages (name) values ("
                        .. quote_sql_str(pkg_name) .. ") returning id"

            local res = query_db(sql)
            pkg_id = res[1].id

        else
            dd("package name found in db.")
            pkg_id = assert(rows[1].id)
        end
    end

    if new_org or (new_user and login == account) then
        dd("new account, no need to check duplicate uploads")

    else
        dd("check if the package with the same verison under ",
            "the same account is already uploaded.")

        local sql
        if login == account then
            -- user account
            assert(user_id)

            sql = "select version_s, created_at from uploads where uploader = "
                  .. user_id
                  .. " and org_account is null and version_v = "
                  .. ver_v
                  .. " and name = " .. quote_sql_str(pkg_name)

        else
            -- org account
            assert(user_id)
            assert(org_id)

            sql = "select version_s, created_at from uploads where uploader = "
                  .. user_id
                  .. " and org_account = "
                  .. org_id
                  .. " and version_v = " .. ver_v
                  .. " and name = " .. quote_sql_str(pkg_name)
        end

        local rows = query_db(sql)
        if #rows == 0 then
            dd("no duplicate uploads found in db")

        else
            local prev_ver_s = rows[1].version_s
            local created_at = rows[1].created_at
            return log_and_out_err(ctx, 400, "duplicate upload: ",
                                   pkg_name, "-", prev_ver_s,
                                   " (previously uploaded at ", created_at,
                                   ").")
        end
    end

    do
        req_read_body()

        local file = req_body_file()
        if not file then
            log_err(ctx, "no request body file")
            return ngx.exit(500)
        end

        local dst_dir = incoming_directory .. "/" .. account
        shell(ctx, "mkdir -p " .. dst_dir)

        local dst_file = dst_dir .. "/" .. fname
        local fh, err = io_open(dst_file, "rb")
        if fh then
            io_close(fh)
            return log_and_out_err(ctx, 400, "duplicate file upload: ", fname)
        end

        dd("cp ", file, " ", dst_file)
        shell(ctx, "cp " .. file .. " " .. dst_file)

        dd("user file: ", fname)
    end

    -- insert the new uploaded task to the uplaods database.

    local sql1 = "insert into uploads (uploader, size, name, checksum, "
                  .. "version_v, version_s, client_addr"

    local sql2 = ""
    if login ~= account then
         sql2 = ", org_account"
    end

    local sql3 = ") values (" .. user_id .. ", " .. size
                 .. ", " .. quote_sql_str(pkg_name)
                 .. ", " .. quote_sql_str(user_md5)
                 .. ", " .. ver_v
                 .. ", " .. quote_sql_str(pkg_version)
                 .. ", " .. quote_sql_str(ngx_var.remote_addr)

    local sql4
    if login ~= account then
        sql4 = ", " .. org_id .. ") returning id"
    else
        sql4 = ") returning id"
    end

    local sql = sql1 .. sql2 .. sql3 .. sql4
    local res = query_db(sql)
    assert(res.affected_rows == 1)

    say("File ", fname, " has been successfully uploaded ",
        "and will be processed by the server shortly.\n",
        "The uploaded task ID is ", res[1].id, ".")
end


function db_insert_user_info(ctx, user_info)
    local u = user_info
    local q = quote_sql_str
    local sql

    sql = "insert into users (login, name, avatar_url, bio, blog, "
          .. "company, location, followers, following, public_email, "
          .. "public_repos, github_created_at, github_updated_at) "
          .. "values ("
          .. q(u.login) .. ", "
          .. q(u.name) .. ", "
          .. q(u.avatar_url) .. ", "
          .. q(u.bio) .. ", "
          .. q(u.blog) .. ", "
          .. q(u.company) .. ", "
          .. q(u.location) .. ", "
          .. q(u.followers) .. ", "
          .. q(u.following) .. ", "
          .. q(u.email) .. ", "
          .. q(u.public_repos) .. ", "
          .. q(u.created_at) .. ", "
          .. q(u.updated_at) .. ") returning id"

    local res = query_db(sql)

    -- say("insert user res: ", cjson.encode(res))
    local user_id = res[1].id

    if not user_id then
        return log_and_out_err(ctx, 500,
                               "failed to create user record ",
                               "in the database")
    end

    return user_id
end


function db_update_user_info(ctx, user_info, user_id)
    local u = user_info
    local q = quote_sql_str
    local sql

    sql = "update users set login = " .. q(u.login)
          .. ", name = " .. q(u.name)
          .. ", avatar_url = " .. q(u.avatar_url)
          .. ", bio = " .. q(u.bio)
          .. ", blog = " .. q(u.blog)
          .. ", company = " .. q(u.company)
          .. ", location = " .. q(u.location)
          .. ", followers = " .. q(u.followers)
          .. ", following = " .. q(u.following)
          .. ", public_email = " .. q(u.email)
          .. ", public_repos = " .. q(u.public_repos)
          .. ", github_created_at = " .. q(u.created_at)
          .. ", github_updated_at = " .. q(u.updated_at)
          .. ", updated_at = now() where id = " .. user_id
                        -- user_id is from db,
                        -- so no injection possible

    local res = query_db(sql)
    -- say("update user res: ", cjson.encode(res))
    assert(res.affected_rows == 1)
end


function query_github_user(ctx, token)
    local path = "/user"
    local res = query_github(ctx, path)

    local scopes = res.headers["X-OAuth-Scopes"]

    if not scopes or not str_find(scopes, "user:email", nil, true) then
        return log_and_out_err(ctx, 403,
                               "personal access token lacking ",
                               "the user:email scope: ", scopes)
    end

    if #scopes > #"read:org, user:email" then
        return log_and_out_err(ctx, 403,
                               "personal access token is too permissive; ",
                               "only the scopes user:email and read:org ",
                               "should be allowed.")
    end

    -- say(cjson.encode(res.headers))

    local json = res.body

    -- say("user json: ", json)

    local data, err = decode_json(json)
    if not data then
        return log_and_out_err(ctx, 502, "failed to parse user json: ",
                               err, " (", json, ")")
    end

    local login = data.login
    if not login then
        return log_and_out_err(ctx, 502,
                               "login name cannot found in the ",
                               "github /user API call: ", json)
    end

    return data, scopes
end


function db_insert_org_info(ctx, org_info)
    local o = org_info
    local q = quote_sql_str
    local sql

    sql = "insert into orgs (login, name, avatar_url, description, blog, "
          .. "company, location, public_email, "
          .. "public_repos, github_created_at, github_updated_at) "
          .. "values ("
          .. q(o.login) .. ", "
          .. q(o.name) .. ", "
          .. q(o.avatar_url) .. ", "
          .. q(o.description) .. ", "
          .. q(o.blog) .. ", "
          .. q(o.company) .. ", "
          .. q(o.location) .. ", "
          .. q(o.email) .. ", "
          .. q(o.public_repos) .. ", "
          .. q(o.created_at) .. ", "
          .. q(o.updated_at) .. ") returning id"

    local res = query_db(sql)

    -- say("insert orgs res: ", cjson.encode(res))
    local org_id = res[1].id

    if not org_id then
        return log_and_out_err(ctx, 500,
                               "failed to create org record ",
                               "in the database")
    end

    return org_id
end


function db_insert_org_ownership(ctx, org_id, user_id)
    -- both org_id and user_id are from our own database.
    local sql = "insert into org_ownership (org_id, user_id) values ("
                .. org_id .. ", " .. user_id .. ")"
    local res = query_db(sql)
    assert(res.affected_rows == 1)
end


function query_github_org(ctx, account)
    local path = "/orgs/" .. account
    local res = query_github(ctx, path)

    local json = res.body

    local data, err = decode_json(json)
    if not data then
        return log_and_out_err(ctx, 502,
                               "failed to parse org membership json: ",
                               err, " (",
                               json, ")")
    end

    return data
end


function query_github_org_ownership(ctx, org, user)
    local path = "/orgs/" .. org .. "/memberships/" .. user
    local res = query_github(ctx, path)

    local json = res.body

    -- say("org membership json: ", json)

    local data, err = decode_json(json)
    if not data then
        return log_and_out_err(ctx, 502,
                               "failed to parse org membership json: ",
                               err, " (",
                               json, ")")
    end

    if data.state ~= "active" or data.role ~= "admin" then
        return log_and_out_err(ctx, 403,
                               'your github account "', user,
                               '" does not own organization "', org,
                               '": ', json)
    end
end


function db_insert_user_verified_email(ctx, user_id, email)
    local sql = "update users set verified_email = " .. quote_sql_str(email)
                .. " where id = " .. user_id
    local res = query_db(sql)
    assert(res.affected_rows == 1)
end


function query_github_user_verified_email(ctx)
    local path = "/user/emails"
    local res = query_github(ctx, path)

    local json = res.body

    -- say("email json: ", json)

    local data, err = decode_json(json)
    if not data then
        return log_and_out_err(ctx, 502,
                               "failed to parse user email json: ",
                               err, " (", json, ")")
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
        return log_and_out_err(ctx, 400,
                               "no verified email address found from ",
                               "github: ", json)
    end

    return email
end


do
    local opm_user_agent = "opm server " .. _M.version
    local MAX_GITHUB_TRIES = 2

    function query_github(ctx, path)
        local httpc = ctx.httpc
        local auth = ctx.auth
        
        if not httpc then
            httpc = http.new()
            ctx.httpc = httpc
        end

        httpc:set_timeout(10 * 1000)  -- 10 sec

        local host = "api.github.com"
        local res, err

        for i = 1, MAX_GITHUB_TRIES do
            local ok
            ok, err = httpc:connect(host, 443)
            if not ok then
                log_err(ctx, i, ": failed to connect to ", host, ": ", err)
                goto continue
            end

            if httpc:get_reused_times() == 0 then
                local ssl_session, err = httpc:ssl_handshake(nil, host, true)
                if not ssl_session then
                    log_err(ctx, i, ": ssl handshake failed with ",
                            host, ": ", err)
                    goto continue
                end
            end

            res, err = httpc:request{
                path = path,
                headers = {
                    Host = host,
                    ["User-Agent"] = opm_user_agent,
                    Authorization = auth,
                    Accept = "application/vnd.github.v3+json",
                },
            }

            if not res then
                log_err(ctx, i, ": failed to send ", host, " request to ",
                        path, ": ", err)
                goto continue
            end

            res.body = res:read_body()

            ok, err = httpc:set_keepalive(10*1000, 2)
            if not ok then
                log_err(ctx, i, ": failed to put the ", host,
                        " conn into pool: ", err)
                goto continue
            end

            break

            ::continue::
        end

        if not res then
            return ngx.exit(500)
        end

        if res.status == 403 then
            ngx.status = 403
            out_err(res.body)
            return ngx.exit(403)
        end

        if res.status ~= 200 then
            local msg = "server " .. host .. " returns bad status code for "
                        .. path .. ": " .. res.status
            log_err(ctx, msg)
            out_err(msg)
            return ngx.exit(500)
        end

        return res
    end
end -- do


function shell(ctx, cmd)
    -- FIXME we should avoid blocking the nginx worker process with shell
    -- commands via something like lua-resty-shell.

    -- assuming the Lua 5.2 semantics of os.execute().
    local status, reason = os_exec(cmd)
    if not status or reason == "signal" then
        log_err(ctx, "failed to run command ", cmd, ": ", reason)
        return ngx.exit(500)
    end
end


local db_spec = {
    host = "127.0.0.1",
    port = "5432",
    database = "opm",
    user = "opm",
    password = "buildecosystem",
}


do
    local MAX_DATABASE_TRIES = 2

    function query_db(query)
        local pg = pgmoon.new(db_spec)

        -- print("sql query: ", query)

        local ok, err

        for i = 1, MAX_DATABASE_TRIES do
            ok, err = pg:connect()
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to database: ", err)
                ngx.sleep(0.1)
            else
                break
            end
        end

        if not ok then
            ngx.log(ngx.ERR, "fatal response due to query failures")
            return ngx.exit(500)
        end

        -- the caller should ensure that the query has no side effects
        local res
        for i = 1, MAX_DATABASE_TRIES do
            res, err = pg:query(query)
            if not res then
                ngx.log(ngx.ERR, "failed to send query \"", query, "\": ", err)

                ngx.sleep(0.1)

                ok, err = pg:connect()
                if not ok then
                    ngx.log(ngx.ERR, "failed to connect to database: ", err)
                    break
                end
            else
                break
            end
        end

        if not res then
            ngx.log(ngx.ERR, "fatal response due to query failures")
            return ngx.exit(500)
        end

        local ok, err = pg:keepalive(0, 5)
        if not ok then
            ngx.log(ngx.ERR, "failed to keep alive: ", err)
        end

        return res
    end
end  -- do


function quote_sql_str(v)
    if not v or v == ngx_null then
        return "null"
    end
    local typ = type(v)
    if typ == "number" or typ == "boolean" then
        return tostring(v)
    end
    return set_quote_sql_str(v)
end


function out_err(...)
    ngx.req.discard_body()
    say("ERROR: ", ...)
end


function log_err(ctx, ...)
    ngx.log(ngx.ERR, "[opm] [", ctx.account or "",
            "] [", ctx.token or "", "] ", ...)
end


function log_and_out_err(ctx, status, ...)
    ngx.status = status
    out_err(...)
    log_err(ctx, ...)
    ngx.exit(status)
end


do
    local ctx = { pos = 1 }
    local ver_v = {}

    function ver2pg_array(ver_s)
        tab_clear(ver_v)

        ctx.pos = 1
        local i = 0
        while true do
            local fr, to, err = re_find(ver_s, [[\d+]], "jo", ctx)
            if not fr then
                assert(not err)
                break
            end

            i = i + 1
            ver_v[i] = sub(ver_s, fr, to)
        end

        return "'{" .. tab_concat(ver_v, ",") .. "}'"
    end
end


return _M