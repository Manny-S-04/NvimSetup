local config = require("sprints.config")

local M = {}

local did_setup = false

--- Configure sprints.nvim. See :help sprints-config for the options.
function M.setup(opts)
  config.setup(opts)
  if not did_setup then
    require("sprints.commands").setup()
    did_setup = true
  end
  return M
end

return M
