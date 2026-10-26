-- On-the-spot workflow guides ("what do I press now?").
--
--   F1            guide for what you're doing right now (debugging, stopped at a breakpoint, C#, tests, git…)
--                 inside it: <CR> on a key line runs it, p pins it, a browses all guides, q / F1 closes
--   <leader>H     browse / fuzzy-search every guide
--   :Guide [name] same as F1, or open one guide by name;  :Guide check  finds guides whose keys no longer exist
--   :Guide edit   open lua/guide/workflows.lua to add your own
--
-- Nothing pops up on its own (no which-key style timeout popups). The only always-on part is the
-- debug hint in the statusline (require("guide").statusline()), shown while a debug session exists.
local M = {}

local ns = vim.api.nvim_create_namespace("guide")
local state = { win = nil, buf = nil, pinned = false, timer = nil, last_ctx = nil, source_win = nil }

local function workflows()
    return require("guide.workflows")
end

-- ── key formatting ────────────────────────────────────────────────────────────────────
local MODS = { C = "Ctrl", S = "Shift", A = "Alt", M = "Alt", D = "Cmd" }

--- "<C-S-b>" -> "Ctrl+Shift+B", "<leader>nd" -> "Space n d", "<F5>" -> "F5"
function M.pretty_key(lhs)
    local out = {}
    local i = 1
    while i <= #lhs do
        local tok = lhs:match("^<[^>]+>", i)
        if tok then
            i = i + #tok
            local inner = tok:sub(2, -2)
            if inner:lower() == "leader" then
                table.insert(out, "Space")
            elseif inner:lower() == "cr" then
                table.insert(out, "Enter")
            elseif inner:lower() == "esc" then
                table.insert(out, "Esc")
            elseif inner:lower() == "tab" then
                table.insert(out, "Tab")
            else
                local parts = vim.split(inner, "-", { plain = true })
                local key = table.remove(parts)
                local names = {}
                for _, p in ipairs(parts) do
                    table.insert(names, MODS[p:upper()] or p)
                end
                if #key == 1 then key = key:upper() end
                table.insert(names, key)
                table.insert(out, table.concat(names, "+"))
            end
        else
            table.insert(out, lhs:sub(i, i))
            i = i + 1
        end
    end
    return table.concat(out, " ")
end

-- ── context ───────────────────────────────────────────────────────────────────────────
local function in_dotnet_project(buf)
    local start = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:h")
    if start == "" or vim.fn.isdirectory(start) == 0 then start = vim.fn.getcwd() end
    return #vim.fs.find(function(name)
        return name:match("%.slnx?$") or name:match("%.[cf]sproj$")
    end, { upward = true, path = start, limit = 1 }) > 0
end

--- Ordered list of context tags, most specific first, plus a human label.
function M.context(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local tags, label = {}, nil
    local ft = vim.bo[buf].filetype

    -- Only look at nvim-dap if it's already loaded: F1 must never cost a plugin load.
    local dap = package.loaded["dap"]
    local session = dap and dap.session()
    if session then
        if session.stopped_thread_id then
            table.insert(tags, "debug-stopped")
            local frame = session.current_frame
            label = "Debugging — paused"
            if frame and frame.source and frame.source.name then
                label = ("Debugging — paused at %s:%d"):format(frame.source.name, frame.line or 0)
            end
        else
            table.insert(tags, "debug-running")
            label = "Debugging — running"
        end
        table.insert(tags, "debug")
    end

    if ft == "easy-dotnet" or ft:match("^neotest") then
        table.insert(tags, "tests")
        label = label or "Test Explorer"
    elseif ft:match("^dapui") or ft == "dap-repl" then
        table.insert(tags, "debug")
        label = label or "Debug windows"
    elseif ft == "fugitive" or ft == "gitcommit" or ft:match("^Diffview") or ft == "git" then
        table.insert(tags, "git")
        label = label or "Git"
    elseif ft:match("^jira") then
        table.insert(tags, "jira")
        label = label or "Jira"
    elseif ft == "qf" or ft == "trouble" then
        table.insert(tags, "errors")
        label = label or "Error list"
    end

    if ft == "cs" or ft == "razor" then
        table.insert(tags, "csharp")
        if vim.api.nvim_buf_get_name(buf):match("[Tt]ests?[/\\]") or vim.api.nvim_buf_get_name(buf):match("Tests?%.cs$") then
            table.insert(tags, "tests")
        end
        label = label or "C#"
    end
    if (ft == "cs" or ft == "razor" or ft == "xml") and in_dotnet_project(buf) then
        table.insert(tags, "dotnet")
        label = label or ".NET project"
    elseif ft == "" and vim.bo[buf].buftype == "" and in_dotnet_project(buf) then
        table.insert(tags, "dotnet")
        label = label or ".NET project"
    end

    table.insert(tags, "general")
    return tags, label or "General"
end

--- Guides relevant to `tags`, ordered by how specific the matching tag is.
function M.matching(tags)
    local rank = {}
    for i, t in ipairs(tags) do rank[t] = rank[t] or i end
    local hits = {}
    for idx, w in ipairs(workflows()) do
        local best
        for _, c in ipairs(w.contexts or {}) do
            if rank[c] and (not best or rank[c] < best) then best = rank[c] end
        end
        if best then table.insert(hits, { w = w, rank = best, idx = idx }) end
    end
    table.sort(hits, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.idx < b.idx
    end)
    return vim.tbl_map(function(h) return h.w end, hits)
end

function M.find(id)
    for _, w in ipairs(workflows()) do
        if w.id == id then return w end
    end
end

-- ── rendering ─────────────────────────────────────────────────────────────────────────
local KEYW = 18

--- Render guides to lines. Returns lines, highlights {line, col_s, col_e, group}, actions {line -> step}
function M.render(list, opts)
    opts = opts or {}
    local lines, hls, actions = {}, {}, {}
    local function add(text, group, action)
        table.insert(lines, text)
        if group then table.insert(hls, { #lines - 1, 0, -1, group }) end
        if action then actions[#lines] = action end
    end

    if opts.header then
        add(" " .. opts.header, "Title")
        add("")
    end

    for wi, w in ipairs(list) do
        if wi > (opts.max_expanded or math.huge) then
            if wi == (opts.max_expanded or 0) + 1 then add(" Also relevant:", "Comment") end
            add(("   %s   (:Guide %s)"):format(w.title, w.id), "Comment", { guide = w.id })
        else
            add(" " .. w.title, "Function", { guide = w.id })
            if w.summary and not opts.compact then add("   " .. w.summary, "Comment") end
            for _, s in ipairs(w.steps) do
                local key = s.keys and M.pretty_key(s.keys) or s.cmd or nil
                if opts.compact and not key then goto continue end
                if key then
                    local text = ("   %-" .. KEYW .. "s %s"):format(key, s.text)
                    add(text, nil, (s.keys or s.cmd) and s or nil)
                    table.insert(hls, { #lines - 1, 3, 3 + #key, s.cmd and "String" or "Special" })
                else
                    add("   • " .. s.text)
                end
                ::continue::
            end
            if wi < #list then add("") end
        end
    end

    if opts.footer then
        add("")
        add(" " .. opts.footer, "NonText")
    end
    return lines, hls, actions
end

-- ── float ─────────────────────────────────────────────────────────────────────────────
local function close()
    if state.timer then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
    end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
    end
    state.win, state.buf, state.pinned, state.last_ctx = nil, nil, false, nil
end
M.close = close

local function run_step(step)
    close()
    if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
        vim.api.nvim_set_current_win(state.source_win)
    end
    vim.schedule(function()
        if step.cmd then
            vim.api.nvim_feedkeys(":" .. step.cmd:gsub("^:", "") .. " ", "n", false)
        elseif step.keys then
            local lhs = step.keys:gsub("<[Ll]eader>", vim.g.mapleader or "\\")
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "m", false)
        end
    end)
end

local function fill(buf, lines, hls)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(hls) do
        local line = lines[h[1] + 1] or ""
        local e = h[3] == -1 and #line or math.min(h[3], #line)
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], h[2], { end_col = e, hl_group = h[4] })
    end
end

local function width_of(lines)
    local w = 30
    for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l) + 2) end
    return math.min(w, vim.o.columns - 4)
end

local open -- forward

local function render_current(opts)
    opts = opts or {}
    local tags, label = M.context(vim.api.nvim_win_get_buf(state.source_win or 0))
    local list = opts.only and { opts.only } or M.matching(tags)
    local footer = state.pinned and "F1 unpin · :Guide to browse"
        or "Enter run key · p pin · a all guides · Space ? search keys · q close"
    local lines, hls, actions = M.render(list, {
        header = opts.only and opts.only.title and "Guide" or ("Now: " .. label),
        footer = footer,
        max_expanded = state.pinned and 1 or (opts.only and 1 or 3),
        compact = state.pinned,
    })
    if opts.only then
        table.remove(lines, 1); table.remove(lines, 1)
        for _, h in ipairs(hls) do h[1] = h[1] - 2 end
        local shifted = {}
        for k, v in pairs(actions) do shifted[k - 2] = v end
        actions = shifted
    end
    return lines, hls, actions, table.concat(tags, ",") .. (opts.only and opts.only.id or "")
end

open = function(opts)
    opts = opts or {}
    if state.win and vim.api.nvim_win_is_valid(state.win) then close() end
    state.source_win = vim.api.nvim_get_current_win()
    state.pinned = opts.pin or false

    local lines, hls, actions, key = render_current(opts)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "guide"
    fill(buf, lines, hls)

    local width = width_of(lines)
    local height = math.min(#lines, vim.o.lines - 6)
    local win = vim.api.nvim_open_win(buf, not state.pinned, {
        relative = "editor",
        anchor = "NE",
        row = 1,
        col = vim.o.columns - 1,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = state.pinned and " guide (pinned) " or " F1 guide ",
        title_pos = "center",
        focusable = not state.pinned,
        zindex = 60,
    })
    vim.wo[win].cursorline = not state.pinned
    vim.wo[win].wrap = false
    state.win, state.buf, state.last_ctx = win, buf, key

    local function bmap(lhs, fn)
        vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
    bmap("q", close)
    bmap("<Esc>", close)
    bmap("<F1>", close)
    bmap("a", function() close(); M.pick() end)
    bmap("p", function() local o = opts; close(); vim.api.nvim_set_current_win(state.source_win); open(vim.tbl_extend("force", o, { pin = true })) end)
    bmap("<CR>", function()
        local a = actions[vim.api.nvim_win_get_cursor(0)[1]]
        if not a then return end
        if a.guide then
            local w = M.find(a.guide)
            close()
            if w then open({ only = w }) end
        else
            run_step(a)
        end
    end)

    if state.pinned then
        -- Follow what you're doing (e.g. running -> paused at a breakpoint) without stealing focus.
        state.timer = vim.uv.new_timer()
        state.timer:start(400, 400, vim.schedule_wrap(function()
            if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return close() end
            local cur = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_get_config(cur).relative == "" then state.source_win = cur end
            local l2, h2, _, k2 = render_current(opts)
            if k2 ~= state.last_ctx then
                state.last_ctx = k2
                fill(state.buf, l2, h2)
                vim.api.nvim_win_set_config(state.win, {
                    relative = "editor", anchor = "NE", row = 1, col = vim.o.columns - 1,
                    width = width_of(l2), height = math.min(#l2, vim.o.lines - 6),
                })
            end
        end))
    else
        -- first key line, so <CR> works straight away
        for i = 1, #lines do
            if actions[i] and not actions[i].guide then
                vim.api.nvim_win_set_cursor(win, { i, 3 })
                break
            end
        end
        vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
    end
end

--- F1: toggle. If a pinned guide is showing, F1 unpins/closes it.
function M.toggle()
    if state.win and vim.api.nvim_win_is_valid(state.win) then return close() end
    open()
end

function M.open_guide(id)
    local w = M.find(id)
    if not w then return vim.notify("No guide called '" .. id .. "' (:Guide check / <leader>H)", vim.log.levels.WARN) end
    open({ only = w })
end

-- ── picker ────────────────────────────────────────────────────────────────────────────
function M.pick()
    local list = workflows()
    local ok = pcall(require, "telescope")
    if not ok then
        return vim.ui.select(list, {
            prompt = "Guides",
            format_item = function(w) return w.title end,
        }, function(w) if w then open({ only = w }) end end)
    end
    local pickers, finders = require("telescope.pickers"), require("telescope.finders")
    local conf = require("telescope.config").values
    local previewers = require("telescope.previewers")
    local actions, astate = require("telescope.actions"), require("telescope.actions.state")
    pickers.new({}, {
        prompt_title = "Guides (how do I…)",
        finder = finders.new_table({
            results = list,
            entry_maker = function(w)
                -- search titles, summaries and step text, so "breakpoint" or "port in use" finds things
                local words = { w.title, w.summary or "", table.concat(w.contexts or {}, " ") }
                for _, s in ipairs(w.steps) do table.insert(words, s.text) end
                return { value = w, display = w.title, ordinal = table.concat(words, " ") }
            end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = previewers.new_buffer_previewer({
            title = "Steps",
            define_preview = function(self, entry)
                local lines, hls = M.render({ entry.value }, {})
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                for _, h in ipairs(hls) do
                    local line = lines[h[1] + 1] or ""
                    local e = h[3] == -1 and #line or math.min(h[3], #line)
                    pcall(vim.api.nvim_buf_set_extmark, self.state.bufnr, ns, h[1], h[2], { end_col = e, hl_group = h[4] })
                end
            end,
        }),
        attach_mappings = function(bufnr)
            actions.select_default:replace(function()
                local e = astate.get_selected_entry()
                actions.close(bufnr)
                if e then open({ only = e.value }) end
            end)
            return true
        end,
    }):find()
end

-- ── check ─────────────────────────────────────────────────────────────────────────────
--- Finds guide steps pointing at keys/commands that don't exist (e.g. after you remap something).
function M.check(silent)
    local problems = {}
    for _, w in ipairs(workflows()) do
        for _, s in ipairs(w.steps) do
            if s.keys and not s.builtin and not s.buffer then
                local found = false
                for _, mode in ipairs(s.modes or { "n" }) do
                    if vim.fn.maparg(s.keys, mode) ~= "" or not vim.tbl_isempty(vim.fn.maparg(s.keys, mode, false, true)) then
                        found = true
                    end
                end
                if not found then
                    table.insert(problems, ("%s: key %s (%s) is not mapped"):format(w.id, s.keys, s.text))
                end
            end
            if s.cmd and not s.builtin then
                local name = s.cmd:gsub("^:", ""):match("^(%S+)")
                if name and vim.fn.exists(":" .. name) ~= 2 then
                    table.insert(problems, ("%s: command :%s does not exist"):format(w.id, name))
                end
            end
        end
    end
    if not silent then
        if #problems == 0 then
            vim.notify("Guides OK: every key and command they mention exists.")
        else
            vim.notify("Guides out of date:\n" .. table.concat(problems, "\n"), vim.log.levels.WARN)
        end
    end
    return problems
end

-- ── statusline (debug hints, visible without pressing anything) ───────────────────────
function M.statusline()
    local dap = package.loaded["dap"]
    local s = dap and dap.session()
    if not s then return "" end
    if s.stopped_thread_id then
        return "⏸ F5 continue · F10 over · F11 into · ⇧F11 out · ⇧F5 stop · F1 help"
    end
    return "▶ debugging · F9 breakpoint · Space dp pause · ⇧F5 stop · F1 help"
end

function M.statusline_active()
    local dap = package.loaded["dap"]
    return dap ~= nil and dap.session() ~= nil
end

-- ── setup ─────────────────────────────────────────────────────────────────────────────
function M.setup()
    vim.keymap.set("n", "<F1>", M.toggle, { desc = "Guide: what can I do here? (F1)" })
    vim.keymap.set("i", "<F1>", function() vim.cmd.stopinsert(); vim.schedule(M.toggle) end, { desc = "Guide (F1)" })
    vim.keymap.set("n", "<leader>H", M.pick, { desc = "Guide: browse all how-tos" })

    vim.api.nvim_create_user_command("Guide", function(o)
        local a = o.args
        if a == "" then
            M.toggle()
        elseif a == "check" then
            M.check()
        elseif a == "pin" then
            open({ pin = true })
        elseif a == "edit" then
            vim.cmd.edit(vim.fn.stdpath("config") .. "/lua/guide/workflows.lua")
        elseif a == "list" then
            M.pick()
        else
            M.open_guide(a)
        end
    end, {
        nargs = "?",
        desc = "Workflow guides",
        complete = function(lead)
            local items = { "check", "pin", "edit", "list" }
            for _, w in ipairs(workflows()) do table.insert(items, w.id) end
            return vim.tbl_filter(function(i) return i:find(lead, 1, true) == 1 end, items)
        end,
    })

    -- :help still works as normal; F1 just opens this instead of the help index.
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("GuideResize", { clear = true }),
        callback = function()
            if state.win and vim.api.nvim_win_is_valid(state.win) then
                vim.api.nvim_win_set_config(state.win, { relative = "editor", anchor = "NE", row = 1, col = vim.o.columns - 1 })
            end
        end,
    })
end

return M
