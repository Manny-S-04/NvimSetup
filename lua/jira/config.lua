local M = {}

local defaults = {
  url = nil,
  -- Jira Cloud: your Atlassian account email (used with an API token, Basic auth).
  -- Jira Server/Data Center: leave nil and set api_token to a Personal Access Token (Bearer auth).
  email = nil,
  api_token = nil,
  -- "cloud" | "server" | nil. nil = auto-detect: *.atlassian.net is Cloud, anything else Server/DC.
  deployment = nil,
  -- request timeout in milliseconds
  timeout = 10000,
  -- JQL behind :JiraMine
  jql_mine = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  max_results = 50,
}

M.options = vim.deepcopy(defaults)

local function env()
  return {
    url = os.getenv("JIRA_URL"),
    email = os.getenv("JIRA_EMAIL"),
    api_token = os.getenv("JIRA_API_TOKEN"),
  }
end

local function present(v)
  return v ~= nil and v ~= ""
end

--- Merge defaults <- environment <- explicit opts (explicit wins).
--- Does not warn about missing values: that happens when a command is actually used,
--- so machines without Jira credentials (e.g. at home) start silently.
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  local from_env = env()

  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), {
    url = from_env.url,
    email = from_env.email,
    api_token = from_env.api_token,
  }, opts)

  return M.options
end

--- @return boolean true when talking to Jira Cloud (REST v3, ADF bodies, accountIds)
function M.is_cloud()
  local o = M.options
  if o.deployment == "cloud" then
    return true
  elseif o.deployment == "server" then
    return false
  end
  return present(o.url) and o.url:match("%.atlassian%.net/?$") ~= nil
end

--- REST API version: Cloud uses v3, Server/Data Center v2.
function M.api_version()
  return M.is_cloud() and "3" or "2"
end

--- Validate the current configuration. Never logs the token itself.
--- @return boolean ok
function M.validate()
  local o = M.options
  local missing = {}

  if not present(o.url) then
    table.insert(missing, "url (JIRA_URL)")
  end
  if not present(o.api_token) then
    table.insert(missing, "api_token (JIRA_API_TOKEN)")
  end
  if M.is_cloud() and not present(o.email) then
    table.insert(missing, "email (JIRA_EMAIL, required for Jira Cloud)")
  end

  if #missing > 0 then
    vim.notify(("jira.nvim: missing configuration: %s"):format(table.concat(missing, ", ")), vim.log.levels.ERROR)
    return false
  end

  return true
end

--- @return boolean true if enough config is present to make a request
function M.is_configured()
  local o = M.options
  if not (present(o.url) and present(o.api_token)) then
    return false
  end
  return not M.is_cloud() or present(o.email)
end

return M
