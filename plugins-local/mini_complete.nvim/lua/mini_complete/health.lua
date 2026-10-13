-- :checkhealth mini_complete
local M = {}

function M.check()
  local health = vim.health
  health.start("mini_complete")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11+ is required (vim.lsp client methods, vim.snippet)")
  end

  local ok_ls = pcall(require, "luasnip")
  local cfg = require("mini_complete").config
  if cfg.luasnip and ok_ls then
    health.ok("LuaSnip found: snippets are listed and LSP snippets expand through it")
  elseif cfg.luasnip then
    health.info("LuaSnip not installed: LSP snippets expand with vim.snippet")
  else
    health.info("luasnip = false: LSP snippets expand with vim.snippet")
  end

  -- :checkhealth runs in its own buffer, so list every running completion server.
  local clients = vim.lsp.get_clients({ method = "textDocument/completion" })
  if #clients == 0 then
    health.warn("no completion-capable LSP server is running (open a file your servers handle)")
  else
    for _, c in ipairs(clients) do
      health.ok(("completion source: %s (%d buffer(s))"):format(c.name, vim.tbl_count(c.attached_buffers)))
    end
  end
end

return M
