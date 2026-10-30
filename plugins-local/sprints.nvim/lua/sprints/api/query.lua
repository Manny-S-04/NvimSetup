-- Queries for :SprintsFind — the Zoho stand-in for jira.nvim's JQL. A spec says where to look
-- (scope) and what to keep; Zoho has no query language, so text goes to its search endpoint
-- and every other condition is applied here, client-side.
local async = require("sprints.api.async")

local M = {}

---@class sprints.QuerySpec
---@field scope "active"|"backlog"|"open"|"all"|nil   nil = active
---@field owner "me"|"unassigned"|nil                 nil = anyone
---@field status "open"|"todo"|"inprogress"|"done"|nil nil = any status category
---@field status_id string|nil                        one exact project status
---@field type_id string|nil
---@field priority_id string|nil
---@field text string|nil                             title words or an item number
---@field created_by_me boolean|nil

M.SCOPES = {
  active = "active sprint",
  backlog = "backlog",
  open = "open sprints + backlog",
  all = "every sprint",
}

M.STATUS = { open = "not done", todo = "to do", inprogress = "in progress", done = "done" }

local CATEGORY = { todo = "new", inprogress = "indeterminate", done = "done" }

--- Does `it` meet every condition in `spec`? Text is matched against key and title (used
--- when the text wasn't already searched server-side). Pure.
---@param it table normalised item
---@param spec sprints.QuerySpec
---@param me string|nil your user id (needed for owner = "me" / created_by_me)
---@param skip_text boolean|nil the server already searched the text
function M.matches(it, spec, me, skip_text)
  local owners = it.owner_ids or {}
  if spec.owner == "me" and not vim.tbl_contains(owners, me) then
    return false
  end
  if spec.owner == "unassigned" and #owners > 0 then
    return false
  end
  if spec.status == "open" and it.status_category == "done" then
    return false
  end
  if CATEGORY[spec.status or ""] and it.status_category ~= CATEGORY[spec.status] then
    return false
  end
  if spec.status_id and it.status_id ~= spec.status_id then
    return false
  end
  if spec.type_id and it.type_id ~= spec.type_id then
    return false
  end
  if spec.priority_id and it.priority_id ~= spec.priority_id then
    return false
  end
  if spec.created_by_me and (me == nil or it.created_by_id ~= me) then
    return false
  end
  if spec.text and not skip_text then
    local t = spec.text:lower()
    local hay = ((it.key or "") .. " " .. (it.summary or "")):lower()
    if not hay:find(t, 1, true) then
      return false
    end
  end
  return true
end

--- One-line description, e.g. 'active sprint · mine · not done · Bug · "login"'. Pure.
---@param spec sprints.QuerySpec
---@param meta table|nil workspace.meta, to name statuses/types/priorities
function M.describe(spec, meta)
  meta = meta or {}
  local function name(tbl, id)
    local row = tbl and tbl[id]
    return row and row.name or id
  end
  local parts = { M.SCOPES[spec.scope or "active"] }
  if spec.owner == "me" then
    table.insert(parts, "mine")
  elseif spec.owner == "unassigned" then
    table.insert(parts, "unassigned")
  end
  if spec.status then
    table.insert(parts, M.STATUS[spec.status])
  end
  if spec.status_id then
    table.insert(parts, "status " .. name(meta.statuses, spec.status_id))
  end
  if spec.type_id then
    table.insert(parts, name(meta.types, spec.type_id))
  end
  if spec.priority_id then
    table.insert(parts, name(meta.priorities, spec.priority_id) .. " priority")
  end
  if spec.created_by_me then
    table.insert(parts, "created by me")
  end
  if spec.text then
    table.insert(parts, '"' .. spec.text .. '"')
  end
  return table.concat(parts, " · ")
end

--- Does the spec need your user id? Pure.
function M.needs_me(spec)
  return spec.owner == "me" or spec.created_by_me == true
end

--- Drop items seen twice (via more than one sprint), keeping the first. Pure.
function M.dedupe(list)
  local out, seen = {}, {}
  for _, it in ipairs(list) do
    if not seen[it.id] then
      seen[it.id] = true
      table.insert(out, it)
    end
  end
  return out
end

--- Sprint ids a scope covers. cb(ids, err).
local function scope_ids(team, project, scope, cb)
  local sprints = require("sprints.api.sprints")
  if scope == "active" then
    return sprints.active(team, project, function(active, err)
      if not active then
        return cb(nil, err)
      end
      if #active == 0 then
        return cb(nil, { message = "no active sprint in this project (try a wider scope)" })
      end
      cb(vim.tbl_map(function(s)
        return s.id
      end, active), nil)
    end)
  end
  if scope == "backlog" then
    return sprints.backlog_id(team, project, function(id, err)
      cb(id and { id } or nil, err)
    end)
  end
  async.all({
    function(done)
      sprints.list(team, project, done)
    end,
    function(done)
      sprints.backlog_id(team, project, function(id)
        done(id or false, nil)
      end)
    end,
  }, function(res, err)
    if not res then
      return cb(nil, err)
    end
    cb(require("sprints.api.find").order(res[1], res[2] or nil, nil, scope), nil)
  end)
end

--- Run a spec. cb(items, note) or cb(nil, err); note mentions failed sprint requests.
---@param on_progress fun(done: integer, total: integer)|nil
function M.run(team, project, spec, cb, on_progress)
  local find = require("sprints.api.find")
  local scope = spec.scope or "active"

  local function keep(found, me, skip_text, note)
    cb(vim.tbl_filter(function(it)
      return M.matches(it, spec, me, skip_text)
    end, M.dedupe(found)), note)
  end

  local function with_me(fn)
    if not M.needs_me(spec) then
      return fn(nil)
    end
    require("sprints.api.workspace").me(team, project, function(me, err)
      if not me then
        return cb(nil, err)
      end
      fn(me)
    end)
  end

  with_me(function(me)
    -- Text over many sprints: Zoho's search (one cheap request per sprint) beats listing them all.
    if spec.text and (scope == "open" or scope == "all") then
      local value = spec.text:match("^[%w%-#]*%d+$") and find.item_number(spec.text) or spec.text
      return find.search(team, project, value, scope, function(found, note)
        if not found then
          return cb(nil, note)
        end
        keep(found, me, true, note)
      end, on_progress)
    end
    scope_ids(team, project, scope, function(ids, err)
      if not ids then
        return cb(nil, err)
      end
      local items = require("sprints.api.items")
      find.run(ids, find.CONCURRENCY, "all", function(sprint, done)
        items.list({ team = team, project = project, sprint = sprint }, done)
      end, function(lists, errors, first_err)
        if errors == #ids and errors > 0 then
          return cb(nil, first_err)
        end
        local all = {}
        for _, l in ipairs(lists) do
          vim.list_extend(all, l)
        end
        local note = errors > 0 and ("%d of %d sprints failed to load (%s)"):format(errors, #ids, first_err and first_err.message or "?") or nil
        keep(all, me, false, note)
      end, on_progress)
    end)
  end)
end

return M
