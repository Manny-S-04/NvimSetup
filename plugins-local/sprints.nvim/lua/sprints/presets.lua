-- Named :SprintsFind queries: config.presets (read-only, from your setup) merged with ones saved
-- from the menu (stdpath("data")/sprints.nvim/presets.json). Saved ones win on a name clash.
-- Ported from jira.nvim's presets; a preset is a query spec (sprints.api.query), not JQL.
local config = require("sprints.config")

local M = {}

---@return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("data"), "sprints.nvim", "presets.json")
end

---@return table<string, sprints.QuerySpec>
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

---@return table<string, sprints.QuerySpec>
function M.all()
  return vim.tbl_extend("force", config.options.presets or {}, read_saved())
end

---@return string[]
function M.names()
  local names = vim.tbl_keys(M.all())
  table.sort(names)
  return names
end

---@param name string
---@param spec sprints.QuerySpec
---@return boolean ok
---@return string|nil err
function M.save(name, spec)
  local saved = read_saved()
  saved[name] = spec
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
