-- Leftover .NET processes after a crash (Windows only).
--
-- Windows doesn't kill children when their parent dies, so a crashed nvim leaves Roslyn,
-- EasyDotnet, netcoredbg and the API you were debugging running (port taken, console grabbed).
--
--   startup        2 s after nvim starts, kill orphans that are clearly ours, and tell you
--   :DotnetCleanup list every .NET tooling process, then kill orphans / everything not this nvim's
--   state file     nvim-data/dotnet-procs.json: .NET repos you've opened + debug targets, so
--                  "clearly ours" can include your API's .exe, not just the tooling
-- The PowerShell side is scripts/dotnet-orphans.ps1, also used by the nv / nv-recover shell functions.
local M = {}

local is_win = vim.fn.has("win32") == 1
local state_file = vim.fn.stdpath("data") .. "/dotnet-procs.json"
local script = vim.fn.stdpath("config") .. "/scripts/dotnet-orphans.ps1"

local function load_state()
    local f = io.open(state_file, "r")
    if not f then return { roots = {}, programs = {} } end
    local ok, s = pcall(vim.json.decode, f:read("*a"))
    f:close()
    s = ok and type(s) == "table" and s or {}
    s.roots, s.programs = s.roots or {}, s.programs or {}
    return s
end

local function remember(kind, value, limit)
    if not value or value == "" then return end
    value = vim.fs.normalize(value):gsub("/", "\\")
    local s = load_state()
    local list = vim.tbl_filter(function(v) return v:lower() ~= value:lower() end, s[kind])
    table.insert(list, 1, value)
    while #list > limit do table.remove(list) end
    s[kind] = list
    local f = io.open(state_file, "w")
    if f then f:write(vim.json.encode(s)); f:close() end
end

--- Remember the .NET repo we're in (only real repos: never $HOME or a drive root, so "an exe under a
--- root" can't match random installed apps).
local function remember_root()
    local found = vim.fs.find(function(name)
        return name:match("%.slnx?$") or name:match("%.[cf]sproj$")
    end, { upward = true, path = vim.fn.getcwd(), limit = 1 })[1]
    if not found then return end
    local root = vim.fs.dirname(found)
    local home = vim.fs.normalize(vim.env.USERPROFILE or vim.env.HOME or "")
    if root:lower() == home:lower() or #root <= 3 then return end
    remember("roots", root, 10)
end

-- PowerShell via -EncodedCommand: works even where the execution policy blocks .ps1 files
-- (common on locked-down work laptops), since policy doesn't apply to -Command input.
local function run(args, cb)
    if not is_win then return cb and cb({}) end
    local f = io.open(script, "r")
    if not f then return vim.notify("dotnet-procs: missing " .. script, vim.log.levels.ERROR) end
    local body = f:read("*a") .. "\n" .. ("Invoke-DotnetOrphans -Self %d -StateFile '%s' %s")
        :format(vim.fn.getpid(), state_file:gsub("'", "''"), args)
    f:close()
    local utf16 = body:gsub(".", "%0\0")
    vim.system({ "powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", vim.base64.encode(utf16) },
        { text = true }, function(r)
            vim.schedule(function()
                local out = vim.trim(r.stdout or "")
                local ok, list = pcall(vim.json.decode, out ~= "" and out or "[]")
                if not ok or type(list) ~= "table" then
                    vim.notify("dotnet-procs: couldn't read process list\n" .. (r.stderr or out), vim.log.levels.WARN)
                    list = {}
                end
                if cb then cb(list) end
            end)
        end)
end

function M.list(cb) run("", cb) end

local function describe(p)
    return ("%-38s pid %-6d %s%s  %s"):format(p.name, p.pid, p.reason, p.orphan and ", ORPHAN" or "",
        p.mine and "(this nvim)" or p.started or "")
end

function M.sweep()
    run("-Kill", function(list)
        local killed = vim.tbl_filter(function(p) return p.killed end, list)
        if #killed > 0 then
            vim.notify("Killed leftovers from a crashed session:\n" .. table.concat(vim.tbl_map(describe, killed), "\n"))
        end
    end)
end

function M.cleanup()
    if not is_win then return vim.notify(":DotnetCleanup is Windows-only") end
    vim.notify("Looking for .NET processes…")
    M.list(function(list)
        if #list == 0 then return vim.notify("No .NET tooling / app processes running.") end
        local orphans = vim.tbl_filter(function(p) return p.autokill end, list)
        local others = vim.tbl_filter(function(p) return not p.mine end, list)
        local lines = vim.tbl_map(describe, list)
        local choice = vim.fn.confirm(table.concat(lines, "\n") .. "\n\nKill which?",
            ("&Orphans (%d)\n&All not this nvim's (%d)\n&Cancel"):format(#orphans, #others), 1)
        if choice == 1 or choice == 2 then
            run(choice == 1 and "-Kill" or "-KillAll", function(after)
                local killed = vim.tbl_filter(function(p) return p.killed end, after)
                vim.notify(#killed == 0 and "Nothing killed." or
                    ("Killed %d:\n%s"):format(#killed, table.concat(vim.tbl_map(describe, killed), "\n")))
            end)
        end
    end)
end

function M.setup()
    vim.api.nvim_create_user_command("DotnetCleanup", M.cleanup, { desc = "Kill leftover Roslyn/netcoredbg/API processes" })
    if not is_win then return end

    vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("DotnetProcs", { clear = true }),
        once = true,
        callback = function()
            vim.defer_fn(function()
                remember_root()
                if vim.g.dotnet_orphan_sweep ~= false then M.sweep() end
            end, 2000)
        end,
    })

    -- Record what the debugger launches, so a crash mid-debug can find your API afterwards.
    local function hook_dap()
        local dap = require("dap")
        dap.listeners.after.launch["dotnet-procs"] = function(session)
            local cfg = session and session.config or {}
            remember("programs", cfg.program, 10)
            pcall(function() require("crash-guard").crumb("Debugger started: " .. vim.fn.fnamemodify(cfg.program or "?", ":t")) end)
        end
        dap.listeners.after.event_terminated["dotnet-procs"] = function()
            pcall(function() require("crash-guard").crumb("Debugger stopped") end)
        end
    end
    if package.loaded["dap"] then
        hook_dap()
    else
        vim.api.nvim_create_autocmd("User", {
            pattern = "LazyLoad",
            callback = function(ev)
                if ev.data == "nvim-dap" then hook_dap(); return true end
            end,
        })
    end
end

return M
