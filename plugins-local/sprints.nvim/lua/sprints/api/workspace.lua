-- Teams (workspaces), projects, and per-project lookup tables (statuses, item types,
-- priorities, users). Items only carry ids for these, so the tables are fetched once per
-- project per session and cached.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")

local M = {}

local meta_cache = {} -- "team/project" -> meta
local me_cache = {} -- "team/project/email" -> user id

function M.clear_cache()
  meta_cache = {}
  me_cache = {}
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
local meta_waiting = {} -- key -> callbacks queued behind an in-flight fetch

--- rows_any across several page bodies.
local function rows_across(bodies, prefixes)
  local out = {}
  for _, b in ipairs(bodies) do
    vim.list_extend(out, rows_any(b, prefixes))
  end
  return out
end

function M.meta(team, project, cb)
  local key = team .. "/" .. project
  if meta_cache[key] then
    return async.ok(cb, meta_cache[key])
  end
  -- Parallel callers (e.g. one items.list per sprint) share one fetch instead of each
  -- firing the same four requests.
  if meta_waiting[key] then
    return table.insert(meta_waiting[key], cb)
  end
  meta_waiting[key] = { cb }
  local function finish(meta, err)
    local queue = meta_waiting[key] or {}
    meta_waiting[key] = nil
    for _, waiter in ipairs(queue) do
      waiter(meta, err)
    end
  end

  local base = ("/team/%s/projects/%s"):format(team, project)
  local function get(path, query)
    return function(done)
      client.request("GET", base .. path, { query = query }, function(result, err)
        done(result and { result.body or {} } or nil, err)
      end)
    end
  end
  local function paged(path, query, prefix)
    return function(done)
      async.pages(base .. path, query, prefix, done)
    end
  end

  async.all({
    get("/itemstatus/", { action = "data" }),
    get("/itemtype/", { action = "alldata" }),
    paged("/priority/", { action = "data" }, "projPriority"),
    paged("/users/", { action = "data" }, "user"), -- paged: a fixed range could miss people
  }, function(results, err)
    if not results then
      return finish(nil, err)
    end
    local status_rows = rows_across(results[1], { "status", "itemStatus", "projItemStatus", "itemstatus", "projStatus" })
    local order = {}
    for _, r in ipairs(status_rows) do
      table.insert(order, r.id)
    end
    local meta = {
      statuses = by_id_with_name(status_rows, { "statusName", "name" }),
      status_order = order,
      types = by_id_with_name(rows_across(results[2], { "projItemType", "itemType" }), { "itemTypeName", "name" }),
      priorities = by_id_with_name(rows_across(results[3], { "projPriority", "priority" }), { "priorityName", "name" }),
      users = by_id_with_name(rows_across(results[4], { "user", "projUser" }), { "userName", "displayName", "name" }),
    }
    meta_cache[key] = meta
    finish(meta, nil)
  end)
end


--- Your Sprints user id: config.user_id, else the project user whose email matches config.email.
function M.me(team, project, cb)
  local o = config.options
  if config.present(o.user_id) then
    return async.ok(cb, tostring(o.user_id))
  end
  if not config.present(o.email) then
    return async.fail(cb, "set user_id (ZOHO_SPRINTS_USER) or email (ZOHO_EMAIL) so I know who you are", "config")
  end
  local cache_key = ("%s/%s/%s"):format(team, project, o.email:lower())
  if me_cache[cache_key] then
    return async.ok(cb, me_cache[cache_key])
  end
  M.meta(team, project, function(meta, err)
    if not meta then
      return cb(nil, err)
    end
    local want = o.email:lower()
    for id, u in pairs(meta.users) do
      local email = decode.pick(u, { "email", "emailId", "mailId", "userEmail", "emailAddress" })
      if type(email) == "string" and email:lower() == want then
        me_cache[cache_key] = id
        return cb(id, nil)
      end
    end
    cb(nil, { message = ("no project user with email %s; set user_id instead"):format(o.email), type = "config" })
  end)
end

return M
