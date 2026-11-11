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
    local group = vim.api.nvim_create_augroup("sprints.nvim", { clear = true })
    -- Item text is prose: wrap it in every window that shows an item (window-local, so the
    -- rest of your windows keep your global 'nowrap').
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      pattern = "sprints:/*",
      callback = function(args)
        if vim.bo[args.buf].filetype == "sprints-item" and config.options.wrap ~= false then
          require("sprints.ui.util").set_wrap(0, true)
        end
      end,
    })
    vim.api.nvim_create_autocmd("BufReadCmd", {
      group = group,
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
