-- Named JQL queries: config.jql_presets (read-only, from your setup) merged with ones saved
-- from the builder (stdpath("data")/jira.nvim/presets.json). Saved ones win on a name clash.
local config = require("jira.config")

local M = {}

---@return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "jira.nvim", "presets.json")
end

---@return table<string, string>
local function read_saved()
  local f = io.open(M.path(), "r")
  if not f then
    return {}
  end
  local raw = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

---@return table<string, string>
function M.all()
  return vim.tbl_extend("force", config.options.jql_presets or {}, read_saved())
end

---@return string[]
function M.names()
  local names = vim.tbl_keys(M.all())
  table.sort(names)
  return names
end

---@param name string
---@param jql string
---@return boolean ok
---@return string|nil err
function M.save(name, jql)
  local saved = read_saved()
  saved[name] = jql
  vim.fn.mkdir(vim.fs.dirname(M.path()), "p")
  local f, err = io.open(M.path(), "w")
  if not f then
    return false, err
  end
  f:write(vim.json.encode(saved))
  f:close()
  return true, nil
end

return M
