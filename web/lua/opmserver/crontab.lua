local _M = {}


local log = require("opmserver.log")
local query_db = require("opmserver.db").query
local common_conf = require("opmserver.conf").load_entry("common")
local run_shell = require("resty.shell").run
local shell_escape = require("opmserver.utils").shell_escape


local ngx = ngx
local ngx_time = ngx.time
local timer_every = ngx.timer.every


local env = common_conf.env
local deferred_deletion_days = common_conf.deferred_deletion_days or 3
local deferred_deletion_seconds = deferred_deletion_days * 86400


local function move_pkg_files(pkg)
    local package_name = shell_escape(pkg.package_name)
    local uploader_name = shell_escape(pkg.uploader_name)
    local version = pkg.version_s
    local tar_path = uploader_name .. "/" .. package_name
                     .. "-" .. version .. ".opm.tar.gz"
    local final_path = "/opm/final/" .. tar_path
    local bak_path = "/opm/bak/" .. tar_path

    local cmd = {"mkdir", "-p", "/opm/bak/" .. uploader_name}
    local ok, stdout, stderr, reason, status = run_shell(cmd)
    if not ok then
        log.error("failed to make dir, stdout: ", stdout,
                ", stderr: ", stderr,
                ", reason: ", reason, ", status: ", status)

        return nil, stderr or reason or "failed to run shell"
    end

    cmd = {"mv", final_path, bak_path}
    ok, stdout, stderr, reason, status = run_shell(cmd)
    if not ok then
        log.error("failed to mv file, stdout: ", stdout,
                ", stderr: ", stderr,
                ", reason: ", reason, ", status: ", status)

        return nil, stderr or reason or "failed to run shell"
    end

    return true
end


local function check_deferred_deletions()
    local sql = [[select uploads.id as pkg_id, package_name, indexed]]
          .. [[, version_s, deleted_at_time]]
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

    local curr_time = ngx_time()
    local pkg_list = res
    for _, pkg in ipairs(pkg_list) do
        local deleted_at_time = pkg.deleted_at_time
        if deleted_at_time + deferred_deletion_seconds <= curr_time then
            local pkg_id = pkg.pkg_id
            sql = "delete from uploads where id = " .. pkg_id
            local res, err = query_db(sql)
            if not res then
                log.error("delete pkg [", pkg_id, "] failed: ", err)
                return
            end

            local ok, err = move_pkg_files(pkg)
            if not ok then
                log.error('move pkg files failed: ', err)
                return
            end

            log.warn("delete pkg successfully: pkg name:", pkg.package_name,
                     ", version:", pkg.version_s,
                     ", uploader: ", pkg.uploader_name)
        end
    end
end


local jobs = {
    {
        interval = (env == 'dev') and 10 or 120,
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
