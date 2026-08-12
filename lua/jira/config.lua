local M = {}

local defaults = {
  url = nil,
  email = nil,
  api_token = nil,
  -- request timeout in milliseconds
  timeout = 10000,
}

M.options = vim.deepcopy(defaults)

local function env()
  return {
    url = os.getenv("JIRA_URL"),
    email = os.getenv("JIRA_EMAIL"),
    api_token = os.getenv("JIRA_API_TOKEN"),
  }
end

--- Merge defaults <- environment <- explicit opts (explicit wins).
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  local from_env = env()

  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), {
    url = from_env.url,
    email = from_env.email,
    api_token = from_env.api_token,
  }, opts)

  M.validate()
  return M.options
end

--- Validate the current configuration. Never logs the token itself.
function M.validate()
  local o = M.options
  local missing = {}

  if not o.url or o.url == "" then
    table.insert(missing, "url")
  end
  if not o.email or o.email == "" then
    table.insert(missing, "email")
  end
  if not o.api_token or o.api_token == "" then
    table.insert(missing, "api_token")
  end

  if #missing > 0 then
    vim.notify(
      ("jira.nvim: missing configuration: %s (set via setup() or JIRA_URL/JIRA_EMAIL/JIRA_API_TOKEN)"):format(
        table.concat(missing, ", ")
      ),
      vim.log.levels.WARN
    )
    return false
  end

  return true
end

--- @return boolean true if enough config is present to make a request
function M.is_configured()
  local o = M.options
  return o.url ~= nil and o.email ~= nil and o.api_token ~= nil and o.url ~= "" and o.email ~= "" and o.api_token ~= ""
end

return M
