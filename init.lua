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

require("vim-options")
require("lazy").setup("plugins")
