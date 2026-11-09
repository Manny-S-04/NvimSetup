-- Sprints and the backlog. In Zoho the backlog is addressed like a sprint
-- (/sprints/<backlogId>/item/), so both feed the same item-list code.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local decode = require("sprints.api.decode")

local M = {}

-- sprintType codes. UNVERIFIED against the docs: confirm with gR (raw) on a sprint list.
M.SPRINT_TYPES = { ["1"] = "upcoming", ["2"] = "active", ["3"] = "completed", ["4"] = "cancelled" }

function M.state_of(row)
  local t = decode.pick(row, { "sprintType", "sprinttype", "type", "sprintStatus", "status" })
  if t == nil then
    return nil
  end
  local s = tostring(t)
  if M.SPRINT_TYPES[s] then
    return M.SPRINT_TYPES[s]
  end
  -- Whole-word names only: a substring test would read "inactive" as "active".
  s = vim.trim(s:lower())
  local ALIASES = {
    upcoming = "upcoming",
    active = "active",
    ["in progress"] = "active",
    inprogress = "active",
    started = "active",
    running = "active",
    completed = "completed",
    complete = "completed",
    closed = "completed",
    cancelled = "cancelled",
    canceled = "cancelled",
  }
  return ALIASES[s] or s
end

function M.normalise(row)
  return {
    id = row.id,
    name = decode.pick(row, { "sprintName", "name" }) or row.id,
    no = decode.pick(row, { "sprintNo", "sprintno" }),
    state = M.state_of(row),
    start_date = decode.pick(row, { "startDate", "startdate", "sprintStartDate" }),
    end_date = decode.pick(row, { "endDate", "enddate", "sprintEndDate" }),
    raw = row,
  }
end

local names = {} -- "team/project" -> { sprint id -> name }, filled by list() and backlog_id()
local backlog_cache = {}

--- Sprint name if known (any list() or backlog_id() call this session teaches it), else nil.
function M.name_of(team, project, sprint_id)
  if sprint_id == nil then
    return nil
  end
  local key = team .. "/" .. project
  if backlog_cache[key] == tostring(sprint_id) then
    return "Backlog"
  end
  return (names[key] or {})[tostring(sprint_id)]
end

-- Picker order: what you're working in first, then what's next, then history.
local STATE_RANK = { active = 1, upcoming = 2, completed = 3, cancelled = 4 }

function M.sort(list)
  table.sort(list, function(a, b)
    local ra, rb = STATE_RANK[a.state] or 5, STATE_RANK[b.state] or 5
    if ra ~= rb then
      return ra < rb
    end
    local na, nb = tonumber(a.no), tonumber(b.no)
    if na and nb and na ~= nb then
      return na > nb -- newest first within a state
    end
    return (a.name or "") > (b.name or "")
  end)
  return list
end

-- One request per sprintType. Zoho's sprints list filters by a `type` JSON array; with no
-- `type` it returned only part of a real project (an upcoming sprint, not the active ones).
M.LIST_TYPES = { 2, 1, 3, 4 }

--- Merge per-type results into sprints. The state comes from the type that was queried
--- (the rows don't reliably carry it). If an id comes back under more than one type, the
--- server ignored `type`, so fall back to whatever the row itself says.
---@param results { code: integer, rows: table[] }[]
function M.from_typed(results)
  local count, first = {}, {}
  for _, res in ipairs(results) do
    for _, r in ipairs(res.rows) do
      count[r.id] = (count[r.id] or 0) + 1
      first[r.id] = first[r.id] or { row = r, code = res.code }
    end
  end
  local out = {}
  for id, hit in pairs(first) do
    local s = M.normalise(hit.row)
    if count[id] == 1 then
      s.state = M.SPRINT_TYPES[tostring(hit.code)] or s.state
    end
    table.insert(out, s)
  end
  return M.sort(out)
end

function M.list(team, project, cb)
  local path = ("/team/%s/projects/%s/sprints/"):format(team, project)
  local fns = {}
  for _, code in ipairs(M.LIST_TYPES) do
    table.insert(fns, function(done)
      async.pages(path, { action = "data", type = { code } }, "sprint", function(bodies, err)
        -- One type failing (e.g. Zoho rejecting a code) shouldn't hide the others.
        done({ code = code, rows = bodies and (async.merge(bodies, "sprint")) or {}, err = err }, nil)
      end)
    end)
  end
  async.all(fns, function(results)
    local errs = vim.tbl_filter(function(r)
      return r.err ~= nil
    end, results)
    if #errs == #results then
      return cb(nil, errs[1].err)
    end
    local out, key = M.from_typed(results), team .. "/" .. project
    names[key] = names[key] or {}
    for _, s in ipairs(out) do
      names[key][s.id] = s.name
    end
    cb(out, nil)
  end)
end

--- Active sprints only (a project can run more than one).
function M.active(team, project, cb)
  M.list(team, project, function(list, err)
    if not list then
      return cb(nil, err)
    end
    cb(vim.tbl_filter(function(s)
      return s.state == "active"
    end, list), nil)
  end)
end

--- Depth-first search for a key, case-insensitively (backlogId's location isn't documented).
--- Skips *_prop maps: there the value is a column index, not an id.
local function find_key(t, wanted, depth)
  if type(t) ~= "table" or depth > 6 then
    return nil
  end
  for k, v in pairs(t) do
    if type(k) == "string" and k:lower() == wanted and (type(v) == "string" or type(v) == "number") then
      return tostring(v)
    end
  end
  for k, v in pairs(t) do
    if not (type(k) == "string" and k:lower():match("_?props?$")) then
      local found = find_key(v, wanted, depth + 1)
      if found then
        return found
      end
    end
  end
  return nil
end
M._find_key = find_key

--- backlogId from project details: the decoded positional row first, then a key search.
function M.backlog_from_details(body, project)
  for _, row in ipairs(decode.rows(body, "project")) do
    if row.id == tostring(project) or #decode.rows(body, "project") == 1 then
      local id = decode.pick(row, { "backlogId", "backlogid", "backLogId" })
      if id then
        return tostring(id)
      end
    end
  end
  return find_key(body, "backlogid", 0)
end

function M.backlog_id(team, project, cb)
  local key = team .. "/" .. project
  if backlog_cache[key] then
    return async.ok(cb, backlog_cache[key])
  end
  client.request("GET", ("/team/%s/projects/%s/"):format(team, project), { query = { action = "details" } },
    function(result, err)
      if not result then
        return cb(nil, err)
      end
      local id = M.backlog_from_details(result.body, project)
      if not id then
        return cb(nil, { message = "project details have no backlogId (see :SprintsRaw project)", type = "api" })
      end
      backlog_cache[key] = id
      cb(id, nil)
    end)
end

return M
