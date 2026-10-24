-- Run from the plugin root:  nvim --headless -u NONE -c "luafile tests/run.lua"
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
package.path = root .. '/tests/?.lua;' .. package.path
vim.o.swapfile = false
vim.o.showmode = false -- keep '-- INSERT --' out of the output
require('mini_complete_spec')
require('helpers').run()
