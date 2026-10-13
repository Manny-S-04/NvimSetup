-- :checkhealth jira
local M = {}

function M.check()
  local health = vim.health
  local config = require("jira.config")
  local o = config.options

  health.start("jira.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10+ is required (vim.system, vim.base64, vim.ui.open)")
  end

  if vim.fn.executable("curl") == 1 then
    health.ok("curl found: " .. vim.fn.exepath("curl"))
  else
    health.error("curl not found on PATH")
  end

  if not o.url or o.url == "" then
    health.error("url is not set (setup({ url = ... }) or JIRA_URL)")
    return
  end
  health.info(("url: %s (%s)"):format(o.url, config.is_cloud() and "Cloud, REST v3" or "Server/Data Center, REST v2"))

  if config.is_cloud() then
    if o.email and o.email ~= "" then
      health.ok("email set (Basic auth with API token)")
    else
      health.error("Jira Cloud needs email (JIRA_EMAIL) alongside the API token")
    end
  else
    health.info(o.email and o.email ~= "" and "email set: using Basic auth" or "no email: using Bearer Personal Access Token")
  end

  if not o.api_token or o.api_token == "" then
    health.error("api_token is not set (JIRA_API_TOKEN)")
    return
  end
  health.ok("api_token set")

  local me, err = require("jira.api.issues").myself()
  if me then
    health.ok("authenticated as " .. (me.displayName or me.name or "?"))
  else
    health.error("request to /myself failed: " .. (err and err.message or "unknown error"))
  end
end

return M
