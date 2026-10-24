-- Crash breadcrumbs, a safer F12, and :Doctor.
--
-- Why: when nvim dies hard (native crash) there's no Lua error to read, and the terminal is left
-- in a weird state. So each session writes a small file saying "I'm alive" plus the last few
-- risky things it did (F12 targets, LSP attach/detach, debugger start/stop). A clean exit marks it
-- clean. Next startup, a session file that's neither clean nor alive = a crash, and you get told
-- what it was doing. :Doctor shows the details plus Windows' own record of the crash.
local M = {}

local dir = vim.fn.stdpath("data") .. "/crash-guard"
local me = vim.fn.getpid()
local file = ("%s/%d.json"):format(dir, me)
local crumbs = {}
local started = os.time()

local function write_state(clean)
    local f = io.open(file, "w")
    if not f then return end
    f:write(vim.json.encode({ pid = me, started = started, clean = clean, cwd = vim.fn.getcwd(), crumbs = crumbs }))
    f:flush() -- the whole point is that this is on disk *before* a crash
    f:close()
end

--- Record something that might be the last thing we did before dying.
function M.crumb(what)
    table.insert(crumbs, os.date("%H:%M:%S ") .. what)
    if #crumbs > 15 then table.remove(crumbs, 1) end
    write_state(false)
end

local function alive(pid)
    local ok, r = pcall(vim.uv.kill, pid, 0)
    return ok and r == 0
end

local function read_json(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local ok, v = pcall(vim.json.decode, s)
    return ok and v or nil
end

local function check_previous_crashes()
    local found
    for name in vim.fs.dir(dir) do
        local pid = tonumber(name:match("^(%d+)%.json$"))
        if pid and pid ~= me then
            local path = dir .. "/" .. name
            local s = read_json(path)
            if s and s.clean then
                os.remove(path)
            elseif s and not alive(pid) then
                if not found or (s.started or 0) > (found.started or 0) then found = s end
                os.remove(path)
            elseif not s then
                os.remove(path)
            end
        end
    end
    if found then
        local f = io.open(dir .. "/last-crash.json", "w")
        if f then f:write(vim.json.encode(found)); f:close() end
        local last = found.crumbs and found.crumbs[#found.crumbs] or "nothing recorded"
        vim.schedule(function()
            vim.notify(("Neovim didn't exit cleanly last time (pid %d).\nLast thing it did: %s\n:Doctor for details · leftover processes are being cleaned up")
                :format(found.pid, last), vim.log.levels.WARN)
        end)
    end
end

-- ── F12 ───────────────────────────────────────────────────────────────────────────────
-- Native vim.lsp.buf.definition instead of telescope 0.1.x's lsp_definitions: fewer layers on the
-- path that crashes, and one result jumps straight there with no picker/preview in between.
local function jump(item)
    vim.cmd("normal! m'") -- so Ctrl+O comes back here
    local buf = item.bufnr or vim.fn.bufadd(item.filename)
    vim.bo[buf].buflisted = true
    vim.api.nvim_win_set_buf(0, buf)
    pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, math.max((item.col or 1) - 1, 0) })
    vim.cmd("normal! zv")
end

function M.goto_definition()
    local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" })
    if #clients == 0 then
        return vim.notify("No language server here can go to definition yet (:CSharpLsp / :Doctor)", vim.log.levels.WARN)
    end
    local from = ("%s:%d"):format(vim.fn.expand("%:t"), vim.fn.line("."))
    M.crumb(("F12 requested at %s (%s)"):format(from, clients[1].name))
    vim.lsp.buf.definition({
        on_list = function(t)
            local items = t.items or {}
            if #items == 0 then return vim.notify("No definition found") end
            M.crumb(("F12 → %s:%d"):format(items[1].filename or "?", items[1].lnum or 0))
            if #items == 1 then return jump(items[1]) end
            vim.fn.setqflist({}, " ", { title = t.title, items = items })
            local ok, builtin = pcall(require, "telescope.builtin")
            if ok then builtin.quickfix() else vim.cmd("botright copen") end
        end,
    })
end

-- ── treesitter guard ──────────────────────────────────────────────────────────────────
-- Use as treesitter's highlight.disable. Huge files are a classic cause of freezes; decompiled
-- metadata (F12 into a NuGet/BCL type) is skipped too because that's where your F12 crash
-- lands — Roslyn's semantic highlighting still colours it. vim.g.ts_skip_decompiled = false undoes it.
function M.ts_disable(_, buf)
    local name = vim.api.nvim_buf_get_name(buf)
    local ok, st = pcall(vim.uv.fs_stat, name)
    if ok and st and st.size > 512 * 1024 then return true end
    if vim.g.ts_skip_decompiled ~= false and (name:find("MetadataAsSource", 1, true) or name:find("DecompilationMetadataAsSource", 1, true)) then
        return true
    end
    return false
end

-- ── :Doctor ───────────────────────────────────────────────────────────────────────────
function M.doctor()
    local out = { "# Doctor", "" }
    local function add(s) table.insert(out, s) end

    add("## Language servers (this buffer)")
    local cs = vim.lsp.get_clients({ bufnr = 0 })
    if #cs == 0 then add("- none attached") end
    for _, c in ipairs(cs) do
        local pid = c.rpc and c.rpc.pid or "?"
        add(("- %s (id %d, pid %s)%s"):format(c.name, c.id, tostring(pid), c:is_stopped() and " STOPPED" or ""))
    end
    add(("- all clients: %d"):format(#vim.lsp.get_clients()))
    add("")

    add("## This session's recent risky actions")
    if #crumbs == 0 then add("- none") end
    for _, c in ipairs(crumbs) do add("- " .. c) end
    add("")

    local last = read_json(dir .. "/last-crash.json")
    add("## Last crash")
    if last then
        add(("- pid %d, started %s, cwd %s"):format(last.pid, os.date("%Y-%m-%d %H:%M", last.started or 0), last.cwd or "?"))
        for _, c in ipairs(last.crumbs or {}) do add("  - " .. c) end
    else
        add("- none recorded")
    end
    add("")
    add("## Windows crash records for nvim.exe (loading…)")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })

    local function append(lines)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    end

    -- Process list (from dotnet-procs) and Windows' Application Error events, both async.
    pcall(function()
        require("dotnet-procs").list(function(procs)
            local l = { "", "## .NET tooling processes" }
            if #procs == 0 then table.insert(l, "- none") end
            for _, p in ipairs(procs) do
                table.insert(l, ("- %s pid %d%s%s"):format(p.name, p.pid, p.orphan and " ORPHAN" or "", p.mine and " (this nvim)" or ""))
            end
            table.insert(l, "- :DotnetCleanup kills orphans")
            append(l)
        end)
    end)

    if vim.fn.has("win32") == 1 then
        local ps = [[Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000;StartTime=(Get-Date).AddDays(-14)} -ErrorAction SilentlyContinue |
  Where-Object { $_.Message -match 'nvim\.exe' } | Select-Object -First 5 | ForEach-Object {
  $m = $_.Message -split "`r?`n"
  '- ' + $_.TimeCreated.ToString('yyyy-MM-dd HH:mm') + '  ' + (($m | Where-Object { $_ -match 'Faulting module name|Exception code' }) -join ' | ') }]]
        vim.system({ "powershell", "-NoProfile", "-NonInteractive", "-Command", ps }, { text = true }, function(r)
            vim.schedule(function()
                local lines = vim.split(vim.trim(r.stdout or ""), "\n", { trimempty = true })
                if #lines == 0 then lines = { "- none in the last 14 days" } end
                table.insert(lines, "- Faulting module tells you who crashed: nvim.exe/lua51.dll = core/Lua, *treesitter*/parser .dll = a parser, ucrtbase/ntdll = memory corruption (often a plugin calling native code)")
                append(lines)
            end)
        end)
    end
end

function M.setup()
    vim.fn.mkdir(dir, "p")
    write_state(false)
    check_previous_crashes()

    local g = vim.api.nvim_create_augroup("CrashGuard", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", { group = g, callback = function() write_state(true) end })
    vim.api.nvim_create_autocmd("LspAttach", {
        group = g,
        callback = function(a)
            local c = vim.lsp.get_client_by_id(a.data.client_id)
            if c then M.crumb(("LSP %s attached to %s"):format(c.name, vim.fn.fnamemodify(a.file, ":t"))) end
        end,
    })
    vim.api.nvim_create_autocmd("LspDetach", {
        group = g,
        callback = function(a)
            local c = vim.lsp.get_client_by_id(a.data.client_id)
            if c then M.crumb(("LSP %s detached"):format(c.name)) end
        end,
    })

    vim.keymap.set("n", "<F12>", M.goto_definition, { desc = "Go to definition (F12)" })
    vim.api.nvim_create_user_command("Doctor", M.doctor, { desc = "Health report: LSP, processes, last crash" })
end

return M
