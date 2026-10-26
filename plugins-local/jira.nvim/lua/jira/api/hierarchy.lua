-- Parent / child relationships between issues.
--
-- Jira Cloud: one "parent" field for everything (epic -> story, story -> sub-task), and JQL
-- `parent = KEY` finds the children. Jira Server/DC: sub-tasks use "parent", but epics link their
-- stories through the "Epic Link" custom field; set `epic_link_field` (e.g. "customfield_10014")
-- in setup() to follow those too.
--
-- Same calling convention as jira.api.issues: pass a callback for async, omit it for blocking.
local client = require("jira.api.client")
local config = require("jira.config")
local issues = require("jira.api.issues")

local M = {}

local function api(path)
  return ("/rest/api/%s%s"):format(config.api_version(), path)
end

--- Pure: the parent of an issue from its raw REST `fields`, or nil.
--- @return { key: string, summary: string|nil, status: string|nil, issue_type: string|nil }|nil
function M.parent_from_fields(fields, epic_link_field)
  fields = fields or {}
  local p = fields.parent
  if type(p) == "table" and p.key then
    local pf = p.fields or {}
    return {
      key = p.key,
      summary = pf.summary,
      status = type(pf.status) == "table" and pf.status.name or nil,
      issue_type = type(pf.issuetype) == "table" and pf.issuetype.name or nil,
    }
  end
  local epic = epic_link_field and fields[epic_link_field]
  if type(epic) == "string" and epic ~= "" then
    return { key = epic }
  end
  return nil
end

--- Pure: JQL queries that find the children of `key`, best first. Later ones are fallbacks for
--- instances that reject the earlier ones (no Rank field, no Epic Link field…).
function M.children_jql(key, opts)
  opts = opts or {}
  local where = ("parent = %s"):format(key)
  if not opts.cloud and opts.epic_link then
    where = ('(parent = %s OR "Epic Link" = %s)'):format(key, key)
  end
  local out = {
    where .. " ORDER BY Rank ASC", -- board order: the order you're meant to do them in
    where .. " ORDER BY key ASC",
  }
  if where ~= ("parent = %s"):format(key) then
    table.insert(out, ("parent = %s ORDER BY key ASC"):format(key))
  end
  return out
end

--- The parent of `key` (nil value + nil err when it has none).
function M.parent(key, cb)
  local epic_field = config.options.epic_link_field
  local wanted = "parent,summary,status,issuetype" .. (epic_field and ("," .. epic_field) or "")
  local path = api(("/issue/%s"):format(client.uri_encode(key)))
  local function transform(result)
    return M.parent_from_fields((result.body or {}).fields, epic_field)
  end
  if cb then
    client.request("GET", path, { query = { fields = wanted } }, function(result, err)
      if not result then return cb(nil, err) end
      cb(transform(result), nil)
    end)
    return
  end
  local result, err = client.request("GET", path, { query = { fields = wanted } })
  if not result then return nil, err end
  return transform(result), nil
end

--- Issues whose parent is `key`. Async only: cb(issues, err).
function M.children(key, cb)
  local queries = M.children_jql(key, {
    cloud = config.is_cloud(),
    epic_link = config.options.epic_link_field ~= nil,
  })
  local i = 0
  local last_err
  local function try_next()
    i = i + 1
    local jql = queries[i]
    if not jql then return cb(nil, last_err) end
    issues.search(jql, function(list, err)
      if list then return cb(list, nil) end
      last_err = err
      -- only fall back on a rejected query; auth/network errors won't get better
      local status = err and err.status
      if status == 400 then return try_next() end
      cb(nil, err)
    end)
  end
  try_next()
end

return M
