-- Instance metadata the JQL builder offers as choices (projects, issue types).
-- Cached for the session: these change rarely and the builder asks for them repeatedly.
local client = require("jira.api.client")
local config = require("jira.config")

local M = {}

---@class jira.Project
---@field key string
---@field name string

---@type jira.Project[]|nil
local projects_cache = nil
---@type string[]|nil
local types_cache = nil

---@param path string
---@return string
local function api(path)
  return ("/rest/api/%s%s"):format(config.api_version(), path)
end

--- Raw project payload -> sorted {key, name} list. Cloud's /project/search pages ({values=[...]});
--- Server/DC's /project is a bare array.
---@param body table
---@return jira.Project[]
function M.parse_projects(body)
  local raw = body.values or body
  ---@type jira.Project[]
  local out = {}
  for _, p in ipairs(raw) do
    if type(p) == "table" and p.key then
      table.insert(out, { key = p.key, name = p.name or p.key })
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end

--- Raw issue type payload -> unique, sorted names. Cloud repeats "Task"/"Bug" once per
--- team-managed project, so dedupe by name (JQL matches by name anyway).
---@param body table
---@return string[]
function M.parse_issue_types(body)
  ---@type table<string, true>
  local seen = {}
  ---@type string[]
  local out = {}
  for _, t in ipairs(body) do
    if type(t) == "table" and t.name and not seen[t.name] then
      seen[t.name] = true
      table.insert(out, t.name)
    end
  end
  table.sort(out)
  return out
end

---@param cb fun(projects: jira.Project[]|nil, err: table|nil)
function M.projects(cb)
  if projects_cache then
    return vim.schedule(function()
      cb(projects_cache, nil)
    end)
  end
  local path = config.is_cloud() and api("/project/search") or api("/project")
  local query = config.is_cloud() and { maxResults = 200, orderBy = "key" } or nil
  client.request("GET", path, { query = query }, function(result, err)
    if not result then
      return cb(nil, err)
    end
    projects_cache = M.parse_projects(result.body or {})
    cb(projects_cache, nil)
  end)
end

---@param cb fun(types: string[]|nil, err: table|nil)
function M.issue_types(cb)
  if types_cache then
    return vim.schedule(function()
      cb(types_cache, nil)
    end)
  end
  client.request("GET", api("/issuetype"), {}, function(result, err)
    if not result then
      return cb(nil, err)
    end
    types_cache = M.parse_issue_types(result.body or {})
    cb(types_cache, nil)
  end)
end

return M
