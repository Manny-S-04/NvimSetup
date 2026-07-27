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

vim.api.nvim_create_user_command("Surround", function(opts)
  local char = opts.args

  if char == nil or char == "" then
    print("Error: Surround expects a character")
    return
  end

  vim.cmd("normal ysiw" .. char)
end, {
  nargs = 1,
})

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

    local cmd = string.format('git --no-pager blame --porcelain -L %d,%d %s', start_line, end_line, file)
    local output = vim.fn.systemlist(cmd)

    if vim.v.shell_error ~= 0 then
        print("Git blame failed!")
        return
    end

    open_scratch_buffer(output, "GitBlame: " .. file .. " [" .. start_line .. "-" .. end_line .. "]")
end, { range = true })

require("vim-options")
require("lazy").setup("plugins")
require('mini_complete').setup()
