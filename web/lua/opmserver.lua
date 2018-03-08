-- Copyright (C) Yichun Zhang (agentzh)


local DEBUG = false
-- local DEBUG = true


local http = require "resty.http"
local cjson = require "cjson.safe"
local ngx = require "ngx"
local pgmoon = require "pgmoon"
local tab_clear = require "table.clear"
local limit_req = require "resty.limit.req"
local templates = require "opmserver.templates"
local email = require "opmserver.email"
local send_email = email.send_mail


local re_find = ngx.re.find
local re_match = ngx.re.match
local str_find = string.find
local ngx_var = ngx.var
local say = ngx.say
local req_read_body = ngx.req.read_body
local decode_json = cjson.decode
local encode_json = cjson.encode
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
local shdict_bad_users = ngx.shared.bad_users


local incoming_directory = "/opm/incoming"
local final_directory = "/opm/final"

local MIN_TARBALL_SIZE = 136


cjson.encode_empty_table_as_object(false)


local _M = {
    version = "0.0.5"
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
local ver2pg_array, tab2pg_array
local count_bad_users


-- an entry point
function _M.do_upload()
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
        dd("token matched in the database.")

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

    -- check if there is too many uploads.

    local block_key = "block-" .. login
    -- ngx.log(ngx.WARN, "block key: ", block_key)
    do
        local val = shdict_bad_users:get(block_key)
        if val then
            return log_and_out_err(ctx, 403, "github ID ", login,
                                   " blocked temporarily due to ",
                                   "too many uploads. Please retry ",
                                   "in a few hours.")
        end
    end

    local quoted_pkg_name = quote_sql_str(pkg_name)
    local ver_v = ver2pg_array(pkg_version)

    if new_org or (new_user and login == account) then
        dd("new account, no need to check duplicate uploads")

    else
        dd("check if the package with the same version under ",
            "the same account is already uploaded.")

        local sql
        if login == account then
            -- user account
            assert(user_id)

            sql = "select version_s, created_at from uploads where uploader = "
                  .. user_id  -- user_id is from our own db
                  .. " and org_account is null and version_v = "
                  .. ver_v
                  .. " and package_name = " .. quoted_pkg_name
                  .. " and failed != true"

        else
            -- org account
            assert(user_id)
            assert(org_id)

            sql = "select version_s, created_at from uploads where uploader = "
                  .. user_id
                  .. " and org_account = "
                  .. org_id
                  .. " and version_v = " .. ver_v
                  .. " and package_name = " .. quoted_pkg_name
                  .. " and failed != true"
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

        -- we simply override the existing file with the same name (if any).

        dd("cp ", file, " ", dst_file)
        shell(ctx, "cp " .. file .. " " .. dst_file)

        dd("user file: ", fname)
    end

    -- insert the new uploaded task to the uplaods database.

    local sql1 = "insert into uploads (uploader, size, package_name, "
                 .. "orig_checksum, version_v, version_s, client_addr"

    local sql2 = ""
    if login ~= account then
         sql2 = ", org_account"
    end

    local sql3 = ") values (" .. user_id .. ", " .. size
                 .. ", " .. quoted_pkg_name  -- from our own db
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

    do
        local count_key = "count-" .. login
        -- ngx.log(ngx.WARN, "count key: ", count_key)

        -- we add the github login name to the black list for 2 hours after 10
        -- uploads in 5 hours.
        count_bad_users(count_key, block_key, 10, 3600 * 5, 3600 * 2)
    end

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
    -- limit github accesses globally

    local zone = "global_github_limit"
    local lim, err = limit_req.new(zone, 1, 5)
    if not lim then
        return log_and_out_err(ctx, 500, "failed to new resty.limit.req: ", err)
    end

    local delay, err = lim:incoming("github", true)
    if not delay then
        if err == "rejected" then
            return log_and_out_err(ctx, 503, "server too busy");
        end
        return log_and_out_err(ctx, 500, "failed to limit req: ", err)
    end

    if delay >= 0.001 then
        local excess = err
        ngx.log(ngx.WARN, "delaying github request, excess: ", excess,
                " by zone ", zone)
        ngx.sleep(delay)
    end

    -- query github

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
                .. ", updated_at = now() where id = " .. user_id

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

        local client_addr = ctx.client_addr
        if not client_addr then
            client_addr = ngx_var.binary_remote_addr
            ctx.client_addr = client_addr
        end

        local block_key = "block-" .. client_addr
        do
            local val = shdict_bad_users:get(block_key)
            if val then
                return log_and_out_err(ctx, 403, "client blocked temporarily ",
                                       "due to too many failed attempt. ",
                                       "Please retry in a few minutes.")
            end
        end

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

        if res.status == 401 or res.status == 403 then
            local count_key = "count-" .. client_addr

            -- we add the client IP to the black list for 1 min after 5
            -- failed attempts in the last 3 min.
            count_bad_users(count_key, block_key, 5, 60 * 3, 60)

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

        -- ngx.log(ngx.WARN, "sql query: ", query)

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
    ngx.log(ngx.ERR, "[opm] [", ctx.account or "", "] ", ...)
end


function log_and_out_err(ctx, status, ...)
    ngx.status = status
    out_err(...)
    log_err(ctx, ...)
    ngx.exit(status)
end


do
    local ctx = { pos = 1 }
    local bits = {}

    function ver2pg_array(ver_s)
        tab_clear(bits)

        ctx.pos = 1
        local i = 0
        while true do
            local fr, to, err = re_find(ver_s, [[\d+]], "jo", ctx)
            if not fr then
                assert(not err)
                break
            end

            i = i + 1
            bits[i] = sub(ver_s, fr, to)
        end

        return "'{" .. tab_concat(bits, ",") .. "}'"
    end

    function tab2pg_array(list)
        tab_clear(bits)

        for i, item in ipairs(list) do
            bits[i] = quote_sql_str(item)
        end

        if #bits == 0 then
            return "'{}'"
        end

        return "ARRAY[" .. tab_concat(bits, ", ") .. "]"
    end
end


-- only for internal use in util/opm-pkg-indexer.pl
function _M.do_incoming()
    local sql = "select uploads.id as id, uploads.package_name as name,"
                .. " version_s, orig_checksum,"
                .. " users.login as uploader, orgs.login as org_account"
                .. " from uploads"
                .. " left join users on uploads.uploader = users.id"
                .. " left join orgs on uploads.org_account = orgs.id"
                .. " where uploads.failed = false and uploads.indexed = false"
                .. " order by uploads.created_at asc limit 50"

    local rows = query_db(sql)

    say(encode_json{
        incoming_dir = incoming_directory,
        final_dir = final_directory,
        uploads = rows
    })
end


do
    local req_body_data = ngx.req.get_body_data
    local rmfile = os.remove

    -- only for internal use in util/opm-pkg-indexer.pl
    function _M.do_processed()
        if req_method() ~= "PUT" then
            return ngx.exit(405)
        end

        local ctx = {}

        req_read_body()

        local json = req_body_data()
        if not json then
            return log_and_out_err(ctx, 400, "no request body found")
        end

        -- do return log_and_out_err(ctx, 400, json) end

        local data, err = decode_json(json)
        if not data then
            return log_and_out_err(ctx, 400,
                                   "failed to parse the request body as JSON: ",
                                   json)
        end

        local id = tonumber(data.id)
        if not id then
            return log_and_out_err(ctx, 400, "bad id value: ", data.id)
        end

        local sql

        local failed = data.failed

        if failed then
            sql = "update uploads set failed = true"
                  .. ", updated_at = now() where id = "
                  .. quote_sql_str(id)

        else
            local authors = data.authors
            if not authors then
                return log_and_out_err(ctx, 400, "no authors defined")
            end

            local authors_v = tab2pg_array(authors)

            local repo_link = data.repo_link
            if not repo_link then
                return log_and_out_err(ctx, 400, "no repo_link defined")
            end

            local is_orig = data.is_original
            if not is_orig or is_orig == ngx_null or is_orig == 0 then
                is_orig = "false"
            else
                is_orig = "true"
            end

            local abstract = data.abstract
            if not abstract then
                return log_and_out_err(ctx, 400, "no abstract defined")
            end

            local licenses = data.licenses
            if not licenses then
                return log_and_out_err(ctx, 400, "no licenses defined")
            end

            for i, license in ipairs(licenses) do
                licenses[i] = quote_sql_str(license)
            end
            local licenses_v = "ARRAY[" .. tab_concat(licenses, ", ") .. "]"

            local final_md5 = data.final_checksum
            if not final_md5 then
                return log_and_out_err(ctx, 400, "no final_checksum defined")
            end

            local dep_pkgs = data.dep_packages
            if not dep_pkgs then
                return log_and_out_err(ctx, 400, "no dep_packages defined")
            end

            local dep_ops = data.dep_operators
            if not dep_ops then
                return log_and_out_err(ctx, 400, "no dep_operators defined")
            end

            local dep_vers = data.dep_versions
            if not dep_vers then
                return log_and_out_err(ctx, 400, "no dep_versions defined")
            end

            -- ngx.log(ngx.WARN, "abstract: ", abstract)

            sql = "update uploads set indexed = true"
                  .. ", updated_at = now(), authors = "
                  .. authors_v .. ", repo_link = "
                  .. quote_sql_str(repo_link) .. ", is_original = "
                  .. is_orig .. ", abstract = "
                  .. quote_sql_str(abstract) .. ", licenses = "
                  .. licenses_v .. ", final_checksum = "
                  .. quote_sql_str(final_md5) .. ", dep_packages = "
                  .. tab2pg_array(dep_pkgs) .. ", dep_operators = "
                  .. tab2pg_array(dep_ops) .. ", dep_versions = "
                  .. tab2pg_array(dep_vers)
                  .. " where id = " .. quote_sql_str(id)
        end

        local res = query_db(sql)
        assert(res.affected_rows == 1)

        local file = data.file
        if not re_find(file, [[.tar.gz$]], "jo") then
            return log_and_out_err(ctx, 400, "bad file path: ", file)
        end

        local ok, err = rmfile(file)
        if not ok then
            log_err("failed to remove file ", file, ": ", err)
        end

        say([[{"success":true}]])

        if failed then
            local sql = "select uploads.version_s as version"
                        .. ", uploads.package_name as pkg"
                        .. ", uploads.created_at as created_at"
                        .. ", users.name as name, users.login as login"
                        .. ", users.verified_email as email"
                        .. ", orgs.login as org"
                        .. " from uploads left join users"
                        .. " on uploads.uploader = users.id"
                        .. " left join orgs on"
                        .. " uploads.org_account = orgs.id"
                        .. " where uploads.id = " .. id

            local rows = query_db(sql)
            if #rows == 0 then
                return log_and_out_err(ctx, 400, "bad id value: ", id)
            end

            local r = rows[1]

            local email = r.email

            assert(email)
            assert(r.login)

            local account
            if r.org and r.org ~= "" and r.org ~= ngx_null then
                account = r.org
            else
                account = r.login
            end

            ctx.account = account

            local block_key = "block-" .. email
            -- ngx.log(ngx.WARN, "block key: ", block_key)
            do
                local val = shdict_bad_users:get(block_key)
                if val then
                    return log_err(ctx, "recipient email address ", email,
                                   " blocked temporarily due to ",
                                   "too many emails.")
                end
            end

            local name = r.name
            if not name or name == "" or name == ngx_null then
                name = r.login
            end

            local version = r.version
            if not version or version == "" or version == ngx_null then
                version = ""
            end

            local title = "FAILED: " .. account .. "/" .. r.pkg
                          .. " " .. version

            local content = data.reason
            if not content or content == "" or content == ngx_null then
                content = "unknown internal error"
            end

            local body = tab_concat{
                "Dear ", name, ",\n\n",
                "I am the indexer program on the OPM package server.\n\n",
                "I just ran into a fatal error ",
                "while processing your package ", account, "/",
                r.pkg, " ", version, ", which was recently uploaded at ",
                r.created_at, " as Task No. ", id,
                ".\n\nThe details are as follows. ",
                "If you still have no clues about the issue,",
                " please concact us through <info@openresty.org>.\n\n",
                "Please remember to provide this ",
                "mail for the reference. Thank you!\n\n------\n",
                content,
                "\n------\n\nBest regards,\nOPM Indexer\n",
            }

            local ok, err = send_email(email, name, title, body)
            if not ok then
                log_err(ctx, "failed to send email to ", email, ": ", err)
                return
            end

            local count_key = "count-" .. email

            -- we add the email address to the black list for 12 hours after
            -- sending 20 emails in the last 24 hours.
            count_bad_users(count_key, block_key, 20, 3600 * 24, 3600 * 12)
        end
    end
end -- do


do
    local unescape_uri = ngx.unescape_uri
    local pkg_fetch
    local bits = {}
    local req_set_uri = ngx.req.set_uri
    local ngx_redirect = ngx.redirect

    function _M.do_pkg_exists()
        local ctx = {}

        local account = unescape_uri(ngx_var.arg_account)
        if not account or account == "" then
            return log_and_out_err(ctx, 400, "no account specified")
        end

        ctx.account = account

        local pkg_name = unescape_uri(ngx_var.arg_name)
        if not pkg_name or pkg_name == "" then
            return log_and_out_err(ctx, 400, "no name specified")
        end

        local op = unescape_uri(ngx_var.arg_op)
        local pkg_ver = unescape_uri(ngx_var.arg_version)

        local found_ver, _, err = pkg_fetch(ctx, account, pkg_name, op,
                                            pkg_ver)
        if not found_ver then
            ngx.status = 404
            say(err)
            ngx.exit(404)
        end

        say(encode_json{found_version = found_ver})
    end


    function _M.do_pkg_fetch()
        local ctx = {}

        local account = unescape_uri(ngx_var.arg_account)
        if not account or account == "" then
            return log_and_out_err(ctx, 400, "no account specified")
        end

        ctx.account = account

        local pkg_name = unescape_uri(ngx_var.arg_name)
        if not pkg_name or pkg_name == "" then
            return log_and_out_err(ctx, 400, "no name specified")
        end

        local op = unescape_uri(ngx_var.arg_op)
        local pkg_ver = unescape_uri(ngx_var.arg_version)

        local found_ver, md5, err = pkg_fetch(ctx, account, pkg_name, op,
                                              pkg_ver, true --[[ latest ]])
        if not found_ver then
            ngx.status = 404
            say(err, ".")
            ngx.exit(404)
        end

        if not md5 then
            return log_and_out_err(ctx, 500, "MD5 checksum not found")
        end

        ngx.header["X-File-Checksum"] = md5

        -- log_err(ctx, "md5: ", encode_json(md5))

        local fname = pkg_name .. "-" .. found_ver .. ".opm.tar.gz"

        ngx_redirect("/api/pkg/tarball/" .. account .. "/" .. fname, 302)
    end


    function pkg_fetch(ctx, account, pkg_name, op, pkg_ver, latest)
        local quoted_pkg_name = quote_sql_str(pkg_name)
        local quoted_account = quote_sql_str(account)

        local user_id, org_id

        local sql = "select id from users where login = " .. quoted_account

        local rows = query_db(sql)

        if #rows == 0 then
            sql = "select id from orgs where login = " .. quoted_account
            rows = query_db(sql)

            if #rows == 0 then
                return nil, nil, "account name " .. account .. " not found"
            end

            org_id = assert(rows[1].id)

        else
            user_id = assert(rows[1].id)
        end

        tab_clear(bits)
        local i = 0

        i = i + 1
        bits[i] = "select version_s"

        if latest then
            i = i + 1
            bits[i] = ", final_checksum"
        end

        i = i + 1
        bits[i] = " from uploads where indexed = true"
                  .. " and package_name = "

        i = i + 1
        bits[i] = quoted_pkg_name

        -- ngx.log(ngx.WARN, "op = ", op, ", pkg ver = ", pkg_ver)

        if op and op ~= "" and pkg_ver and pkg_ver ~= "" then
            if op == "eq" then
                i = i + 1
                bits[i] = " and version_s = "

                i = i + 1
                bits[i] = quote_sql_str(pkg_ver)

            elseif op == "ge" then
                i = i + 1
                bits[i] = " and version_v >= "

                i = i + 1
                bits[i] = ver2pg_array(pkg_ver)

            elseif op == "gt" then
                i = i + 1
                bits[i] = " and version_v > "

                i = i + 1
                bits[i] = ver2pg_array(pkg_ver)

            else
                return nil, nil, "bad op argument value: " .. op
            end
        else
            op = nil
            pkg_ver = nil
        end

        if user_id then
            i = i + 1
            bits[i] = " and org_account is null and uploader = "

            i = i + 1
            bits[i] = user_id

        else
            i = i + 1
            bits[i] = " and org_account = "

            i = i + 1
            bits[i] = org_id
        end

        if latest then
            i = i + 1
            bits[i] = " order by version_v desc"
        end

        i = i + 1
        bits[i] = " limit 1"

        sql = tab_concat(bits)
        rows = query_db(sql)

        if #rows == 0 then

            local spec

            if op then
                if op == 'ge' then
                    spec = ' >= ' .. pkg_ver

                elseif op == 'gt' then
                    spec = ' > ' .. pkg_ver

                else
                    spec = ' = ' .. pkg_ver
                end

            else
                spec = ""
            end

            return nil, nil, "package " .. pkg_name .. spec
                             .. " not found under account " .. account
        end

        return assert(rows[1].version_s),
               latest and assert(rows[1].final_checksum) or nil
    end
end  -- do


function _M.get_final_directory()
    return final_directory
end


function count_bad_users(count_key, block_key, max_failed, count_time, ban_time)
    local ok, err = shdict_bad_users:add(count_key, 0, count_time)
    if not ok and err ~= "exists" then
        ngx.log(ngx.ERR, "failed to add key ", count_key, ": ",
                err)
        return
    end

    local newval, err = shdict_bad_users:incr(count_key, 1)
    if not newval then
        ngx.log(ngx.ERR, "failed to incr ", count_key, ": ", err)
        return
    end

    if newval and newval >= max_failed then
        shdict_bad_users:delete(count_key)

        local ok, err =
            shdict_bad_users:add(block_key, 1, ban_time)

        if not ok and err ~= "exists" then
            ngx.log(ngx.ERR, "failed to add key ", block_key, ": ",
                    err)
            return
        end
    end
end


do
    local unescape_uri = ngx.unescape_uri
    local results = {}
    local str_rep = string.rep
    local ngx_print = ngx.print

    function _M.do_pkg_search()
        local query = unescape_uri(ngx_var.arg_q)

        local ctx = {}

        if not query or query == "" or #query > 128 then
            return log_and_out_err(ctx, 400, "bad search query value.")
        end

        if re_find(query, [=[[^-. \w]]=], "jo") then
            return log_and_out_err(ctx, 400, "bad search query value.")
        end

        local sql = "select abstract, package_name, orgs.login as org_name"
                    .. ", users.login as uploader_name"
                    .. " from (select last(abstract) as abstract"
                    .. ", package_name, org_account, uploader"
                    .. ", ts_rank_cd(last(ts_idx), last(q), 1) as rank"
                    .. " from uploads, plainto_tsquery("
                    .. quote_sql_str(query) .. ") q"
                    .. " where indexed = true and ts_idx @@ q"
                    .. " group by package_name, uploader, org_account"
                    .. " order by rank desc limit 50) as tmp"
                    .. " left join users on tmp.uploader = users.id"
                    .. " left join orgs on tmp.org_account = orgs.id"

        local rows = query_db(sql)
        -- say(encode_json(rows))

        if #rows == 0 then
            ngx.status = 404
            say("no search result found.")
            return ngx.exit(404)
        end

        tab_clear(results)

        local i = 0
        for _, row in ipairs(rows) do
            local uploader = row.uploader_name
            local org = row.org_name
            local pkg = row.package_name

            local account
            if org and org ~= ngx_null then
                account = org

            else
                account = uploader
            end

            i = i + 1
            results[i] = account

            i = i + 1
            results[i] = "/"

            i = i + 1
            results[i] = pkg

            local len = #account + #pkg + 1

            if len < 50 then
                len = 50 - len
            else
                len = 4
            end

            i = i + 1
            results[i] = str_rep(" ", len)

            i = i + 1
            results[i] = row.abstract

            i = i + 1
            results[i] = "\n"
        end

        ngx_print(results)
    end


    function _M.do_pkg_name_search()
        local query = unescape_uri(ngx_var.arg_q)

        local ctx = {}

        if not query or query == "" or #query > 256 then
            return log_and_out_err(ctx, 400, "bad search query value")
        end

        if not re_find(query, [[^[-\w]+$]], "jo") then
            return log_and_out_err(ctx, 400, "bad search query value")
        end

        local sql = "select is_original, abstract, package_name"
                    .. ", users.login as uploader_name"
                    .. ", orgs.login as org_name"
                    .. " from (select last(is_original) as is_original"
                    .. ", last(abstract) as abstract"
                    .. ", package_name, org_account, uploader"
                    .. " from uploads"
                    .. " where indexed = true and"
                    .. " package_name = " .. quote_sql_str(query)
                    .. " group by package_name, uploader, org_account) as tmp"
                    .. " left join users on tmp.uploader = users.id"
                    .. " left join orgs on tmp.org_account = orgs.id"
                    .. " order by is_original desc, users.followers desc"
                    .. " limit 50"

        local rows = query_db(sql)
        -- say(encode_json(rows))

        if #rows == 0 then
            ngx.status = 404
            say("package not found.")
            return ngx.exit(404)
        end

        tab_clear(results)

        local i = 0
        for _, row in ipairs(rows) do
            local uploader = row.uploader_name
            local org = row.org_name
            local pkg = row.package_name

            local account
            if org and org ~= "" and org ~= ngx_null then
                account = org

            else
                account = uploader
            end

            i = i + 1
            results[i] = account

            i = i + 1
            results[i] = "/"

            i = i + 1
            results[i] = pkg

            local len = #account + #pkg + 1

            if len < 50 then
                len = 50 - len
            else
                len = 4
            end

            i = i + 1
            results[i] = str_rep(" ", len)

            i = i + 1
            results[i] = row.abstract

            i = i + 1
            results[i] = "\n"
        end

        ngx_print(results)

    end
end


function _M.do_index_page()
    local sql = [[select package_name, version_s, abstract, indexed]]
                .. [[, failed, users.login as uploader_name]]
                .. [[, orgs.login as org_name, repo_link]]
                .. [[, uploads.created_at as created_at]]
                .. [[ from uploads]]
                .. [[ left join users on uploads.uploader = users.id]]
                .. [[ left join orgs on uploads.org_account = orgs.id]]
                .. [[ order by uploads.updated_at desc limit 1000]]

    local recent_uploads = query_db(sql)

    sql = [[select count(*) as total,
count(distinct uploader) as uploaders,
count(distinct package_name) as pkg_count
from uploads where indexed = true]]

    local rows = query_db(sql)
    assert(#rows == 1)
    local row = rows[1]

    local total_uploads = row.total
    local uploader_count = row.uploaders
    local pkg_count = row.pkg_count

    local html = templates.process("index.tt2", {
        recent_uploads = recent_uploads,
        total_uploads = total_uploads,
        uploader_count = uploader_count,
        package_count = pkg_count,
    })
    say(html)
end


return _M
