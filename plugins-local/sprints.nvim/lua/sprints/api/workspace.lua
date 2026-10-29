-- Teams (workspaces), projects, and per-project lookup tables (statuses, item types,
-- priorities, users). Items only carry ids for these, so the tables are fetched once per
-- project per session and cached.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")

local M = {}

local meta_cache = {} -- "team/project" -> meta

function M.clear_cache()
  meta_cache = {}
end

--- Rows from whichever of several candidate prefixes the body actually uses.
local function rows_any(body, prefixes)
  for _, p in ipairs(prefixes) do
    local rows = decode.rows(body, p)
    if #rows > 0 then
      return rows
    end
  end
  return {}
end
M.rows_any = rows_any

--- @return { id: string, name: string }[]
function M.teams(cb)
  client.request("GET", "/teams/", {}, function(result, err)
    if not result then
      return cb(nil, err)
    end
    local out = {}
    for _, p in ipairs((result.body or {}).portals or {}) do
      table.insert(out, { id = tostring(p.zsoid or p.teamId or p.id), name = p.teamName or p.name, url_name = p.orgName })
    end
    cb(out, nil)
  end)
end

--- @return { id: string, name: string }[]
function M.projects(team, cb)
  async.pages(("/team/%s/projects/"):format(team), { action = "allprojects" }, "project", function(bodies, err)
    if not bodies then
      return cb(nil, err)
    end
    local rows = async.merge(bodies, "project")
    local out = {}
    for _, r in ipairs(rows) do
      table.insert(out, { id = r.id, name = decode.pick(r, { "projName", "projectName", "name" }) or r.id, raw = r })
    end
    cb(out, nil)
  end)
end

local function by_id_with_name(rows, name_fields)
  local out = {}
  for _, r in ipairs(rows) do
    r.name = decode.pick(r, name_fields) or r.name
    out[r.id] = r
  end
  return out
end

--- Lookup tables for one project.
--- @return { statuses: table, types: table, priorities: table, users: table, status_order: string[] }
function M.meta(team, project, cb)
  local key = team .. "/" .. project
  if meta_cache[key] then
    return async.ok(cb, meta_cache[key])
  end
  local base = ("/team/%s/projects/%s"):format(team, project)
  local function get(path, query)
    return function(done)
      client.request("GET", base .. path, { query = query }, function(result, err)
        done(result and (result.body or {}) or nil, err)
      end)
    end
  end

  async.all({
    get("/itemstatus/", { action = "data" }),
    get("/itemtype/", { action = "alldata" }),
    get("/priority/", { action = "data", index = 1, range = 100 }),
    get("/users/", { action = "data", index = 1, range = 300 }),
  }, function(bodies, err)
    if not bodies then
      return cb(nil, err)
    end
    local status_rows = rows_any(bodies[1], { "status", "itemStatus", "projItemStatus", "itemstatus", "projStatus" })
    local order = {}
    for _, r in ipairs(status_rows) do
      table.insert(order, r.id)
    end
    local meta = {
      statuses = by_id_with_name(status_rows, { "statusName", "name" }),
      status_order = order,
      types = by_id_with_name(rows_any(bodies[2], { "projItemType", "itemType" }), { "itemTypeName", "name" }),
      priorities = by_id_with_name(rows_any(bodies[3], { "projPriority", "priority" }), { "priorityName", "name" }),
      users = by_id_with_name(rows_any(bodies[4], { "user", "projUser" }), { "userName", "displayName", "name" }),
    }
    meta_cache[key] = meta
    cb(meta, nil)
  end)
end

local me_cache = nil

--- Your Sprints user id: config.user_id, else the project user whose email matches config.email.
function M.me(team, project, cb)
  local o = config.options
  if config.present(o.user_id) then
    return async.ok(cb, tostring(o.user_id))
  end
  if me_cache then
    return async.ok(cb, me_cache)
  end
  if not config.present(o.email) then
    return async.fail(cb, "set user_id (ZOHO_SPRINTS_USER) or email (ZOHO_EMAIL) so I know who you are", "config")
  end
  M.meta(team, project, function(meta, err)
    if not meta then
      return cb(nil, err)
    end
    local want = o.email:lower()
    for id, u in pairs(meta.users) do
      local email = decode.pick(u, { "email", "emailId", "mailId", "userEmail", "emailAddress" })
      if type(email) == "string" and email:lower() == want then
        me_cache = id
        return cb(id, nil)
      end
    end
    cb(nil, { message = ("no project user with email %s; set user_id instead"):format(o.email), type = "config" })
  end)
end

return M
