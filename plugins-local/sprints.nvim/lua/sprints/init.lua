local config = require("sprints.config")

local M = {}

local did_setup = false

--- Configure sprints.nvim. See :help sprints-config for the options.
function M.setup(opts)
  config.setup(opts)
  if not did_setup then
    require("sprints.commands").setup()
    -- Reopen items by name (sprints://I22516): harpoon, :e, sessions. "sprints:/*" also matches
    -- the name with its slashes collapsed. Lazy-loading users also need
    -- `event = "BufReadCmd sprints:/*"` in their spec, so this exists before a command runs.
    vim.api.nvim_create_autocmd("BufReadCmd", {
      group = vim.api.nvim_create_augroup("sprints.nvim", { clear = true }),
      pattern = "sprints:/*",
      callback = function(args)
        require("sprints.ui.item").read_cmd(args.buf)
      end,
    })
    did_setup = true
  end
  return M
end

return M
