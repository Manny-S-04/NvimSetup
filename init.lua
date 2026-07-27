local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end

vim.opt.rtp:prepend(lazypath)

vim.api.nvim_create_user_command("Lorem", function()
    vim.cmd([[
        put ='Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.'
    ]])
end, {})

vim.api.nvim_create_user_command("Surround", function(opts)
    local char = opts.args

    local pairs = {
        ['"'] = { '"', '"' },
        ["'"] = { "'", "'" },
        ["`"] = { "`", "`" },
        ["("] = { "(", ")" },
        [")"] = { "(", ")" },
        ["["] = { "[", "]" },
        ["]"] = { "[", "]" },
        ["{"] = { "{", "}" },
        ["}"] = { "{", "}" },
        ["<"] = { "<", ">" },
        [">"] = { "<", ">" },
    }

    local pair = pairs[char]

    if not pair then
        print("Error: unsupported surround: " .. char)
        return
    end

    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local srow, scol = start_pos[2], start_pos[3]
    local erow, ecol = end_pos[2], end_pos[3]

    local lines = vim.api.nvim_buf_get_text(
        0,
        srow - 1,
        scol - 1,
        erow - 1,
        ecol,
        {}
    )

    local text = table.concat(lines, "\n")

    local wrapped = pair[1] .. text .. pair[2]

    vim.api.nvim_buf_set_text(
        0,
        srow - 1,
        scol - 1,
        erow - 1,
        ecol,
        { wrapped }
    )
end, { range = true, nargs = 1 })

function Add(paths)
    if type(paths) ~= "table" then
        print("Error: Add expects a table of paths")
        return
    end

    for _, path in ipairs(paths) do
        local cmd = "git add " .. path
        local result = vim.fn.system(cmd)
        print(result)
    end
end

vim.api.nvim_create_user_command("Add", function(opts)
    local paths = {}
    for path in string.gmatch(opts.args, "%S+") do
        table.insert(paths, path)
    end
    Add(paths)
end, {nargs = "+"})

function Restore(paths)
    if type(paths) ~= "table" then
        print("Error: Restore expects a table of paths")
        return
    end

    for _, path in ipairs(paths) do
        local cmd = "git restore " .. path
        local result = vim.fn.system(cmd)
        print(result)
    end
end

vim.api.nvim_create_user_command("Restore", function(opts)
    local paths = {}
    for path in string.gmatch(opts.args, "%S+") do
        table.insert(paths, path)
    end
    Restore(paths)
end, {nargs = "+"})

function ClearBuffers(buffers)
    if type(buffers) ~= "table" then
        print("Error: Restore expects a table of paths")
        return
    end

    for _, path in ipairs(buffers) do
        local cmd = "bd! " .. path
        local result = vim.cmd(cmd)
        print(result)
    end
end

vim.api.nvim_create_user_command("CB", function(opts)
    local paths = {}
    for path in string.gmatch(opts.args, "%S+") do
        table.insert(paths, path)
    end
    ClearBuffers(paths)
end, {nargs = "+"})

vim.api.nvim_create_user_command("LSB", function()
    vim.cmd("new")
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.fn.execute("ls"), "\n"))
end, {})

local function open_scratch_buffer(lines, title)
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(buf, title or "[Scratch]")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.api.nvim_command("topleft split")
    vim.api.nvim_win_set_buf(0, buf)

    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
end

vim.api.nvim_create_user_command("Glame", function(opts)
    local start_line = opts.line1
    local end_line = opts.line2

    if start_line == 0 or end_line == 0 then
        local ok, s = pcall(vim.fn.line, "'<")
        local ok2, e = pcall(vim.fn.line, "'>")
        if not ok or not ok2 or s < 1 or e < 1 then
            print("No visual selection or range!")
            return
        end
        start_line, end_line = s, e
        if start_line > end_line then
            start_line, end_line = end_line, start_line
        end
    end

    local file = vim.fn.expand('%')
    if file == '' then
        print("No file found!")
        return
    end

    local cmd = string.format('git --no-pager blame --date=short --porcelain -L %d,%d %s', start_line, end_line, file)
    local output = vim.fn.systemlist(cmd)

    local function format_time(ts)
        ts = tonumber(ts)
        if not ts then return ts end
        return os.date("%d-%m-%Y %H:%M:%S", ts)
    end

    for i, line in ipairs(output) do
        local key, value = line:match("^(author%-time)%s+(%d+)$")
        if key then
            output[i] = "author-time " .. format_time(value)
        else
            key, value = line:match("^(committer%-time)%s+(%d+)$")
            if key then
                output[i] = "committer-time " .. format_time(value)
            end
        end
    end

    if vim.v.shell_error ~= 0 then
        print("Git blame failed!")
        return
    end

    open_scratch_buffer(output, "GitBlame: " .. file .. " [" .. start_line .. "-" .. end_line .. "]")
end, { range = true })

local function open_repl(cmd, title)
    local buf = vim.api.nvim_create_buf(false, true)

    vim.api.nvim_buf_set_name(buf, title or "[REPL]")

    vim.cmd("topleft split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    vim.fn.termopen(cmd)

    vim.bo[buf].bufhidden = "wipe"
end

vim.api.nvim_create_user_command("Node", function()
    open_repl("Node", "[Node Terminal]")
end, { range = true })

vim.api.nvim_create_user_command("Python", function()
    open_repl("Python", "[Python Terminal]")
end, { range = true })

vim.api.nvim_create_user_command("Log", function(opts)
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local start_row = start_pos[2] - 1
    local start_col = start_pos[3] - 1

    local end_row = end_pos[2] - 1
    local end_col = end_pos[3]

    local text = vim.api.nvim_buf_get_text(
        0,
        start_row,
        start_col,
        end_row,
        end_col,
        {}
    )

    text = table.concat(text, "\n")

    local line = vim.api.nvim_get_current_line()
    local indent = line:match("^%s*") or ""

    local log_line

    if opts.args == "-cs" then
        log_line = indent .. string.format("Console.WriteLine(%s);", text)
    elseif opts.args == "-rs" then
        log_line = indent .. string.format('println!("{}", %s);', text)
    elseif opts.args == "-c" then
        log_line = indent .. string.format('printf("%%s", %s);', text)
    else
        log_line = indent .. string.format("console.log(%s);", text)
    end

    vim.api.nvim_buf_set_lines(
        0,
        end_row + 1,
        end_row + 1,
        false,
        { log_line }
    )
end, {
        nargs = "?",
        range = true,
    })

require("vim-options")
require("lazy").setup("plugins")
require('mini_complete').setup()
