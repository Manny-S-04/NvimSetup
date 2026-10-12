-- Turns configuration into HTTP auth headers.
-- Isolated so that additional auth mechanisms (OAuth etc.) can be added later
-- without touching client.lua or issues.lua.
local M = {}

local function present(v)
  return v ~= nil and v ~= ""
end

--- @param cfg table jira.config.options-shaped table
--- @return table headers
function M.headers(cfg)
  if not present(cfg.api_token) then
    error("jira.nvim: no API token configured (set JIRA_API_TOKEN or api_token)")
  end

  -- Cloud (and Server with basic auth): email + API token.
  if present(cfg.email) then
    return { Authorization = "Basic " .. vim.base64.encode(cfg.email .. ":" .. cfg.api_token) }
  end

  -- Server / Data Center Personal Access Token.
  return { Authorization = "Bearer " .. cfg.api_token }
end

return M
