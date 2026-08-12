local config = require("jira.config")
local commands = require("jira.commands")

local M = {}

local did_setup = false

--- Configure and initialize jira.nvim.
---@param opts table|nil see jira.config for accepted keys
function M.setup(opts)
  config.setup(opts)

  if not did_setup then
    commands.setup()
    did_setup = true
  end

  return M
end

return M
