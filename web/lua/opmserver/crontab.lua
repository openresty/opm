local _M = {}


local log = require("opmserver.log")
local query_db = require("opmserver.db").query
local q = require("opmserver.db").quote

local ngx = ngx
local ngx_time = ngx.time
local timer_every = ngx.timer.every


local function check_deferred_deletions()
    local sql = [[select uploads.id as pkg_id, package_name, indexed]]
          .. [[, failed, users.login as uploader_name]]
          .. [[, orgs.login as org_name from uploads]]
          .. [[ left join users on uploads.uploader = users.id]]
          .. [[ left join orgs on uploads.org_account = orgs.id]]
          .. [[ where uploads.is_deleted = true]]
    local res, err = query_db(sql)
    if not res then
        log.error("get deferred deletions failed: ", err)
        return nil, err
    end

    local pkg_list = res
    for _, pkg in ipairs(pkg_list) do
        local pkg_id = pkg.pkg_id
        sql = "delete from uploads where id = " .. pkg_id
        local res, err = query_db(sql)
        if not res then
            log.error("delete pkg [", pkg_id, "] failed: ", err)
        end

        -- TODO: remove related files

        log.error("delete pkg successfully: pkg name:", pkg.package_name,
                   ", uploader: ", pkg.uploader_name)
    end
end


local jobs = {
    {
        interval = 60 * 60 * 10,
        handler = check_deferred_deletions,
    },
}

local function timer_handler(premature)
    if premature then
        return
    end

    for _, job in ipairs(jobs) do
        local next_time = job.next_time
        local now = ngx_time()

        if not next_time then
            if job.initiate then
                -- crontab job will start after at 3-10 seconds
                next_time = math.random(3, 10) + now

            else
                -- crontab job will start after at least 10 seconds
                next_time = math.random(10, job.interval) + now
            end

            job.next_time = next_time
            job.running_num = 0
        end

        if next_time <= now
            and (not job.concurrency or job.running_num < job.concurrency)
        then
            job.next_time = now + job.interval

            job.running_num = job.running_num + 1

            local ok, err = pcall(job.handler)
            if not ok then
                log.error("failed to run crontab job: ", err)
            end

            job.running_num = job.running_num - 1

            if ngx.worker.exiting() then
                break
            end
        end
    end
end


function _M.init_worker()
    local ok, err = timer_every(1, timer_handler)
    if not ok then
        log.crit("failed to create every timer: ", err)
    end
end


return _M
