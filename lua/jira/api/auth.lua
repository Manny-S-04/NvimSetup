-- Turns configuration into HTTP auth headers.
-- Isolated so that additional auth mechanisms (OAuth, PAT-only servers,
-- etc.) can be added later without touching client.lua or issues.lua.
local M = {}

--- @param cfg table jira.config.options-shaped table
--- @return table headers
function M.headers(cfg)
  if cfg.api_token and cfg.email and cfg.api_token ~= "" and cfg.email ~= "" then
    local raw = cfg.email .. ":" .. cfg.api_token
    local encoded = vim.base64.encode(raw)
    return { Authorization = "Basic " .. encoded }
  end

  error("jira.nvim: no supported authentication method is configured (need url, email, api_token)")
end

return M
