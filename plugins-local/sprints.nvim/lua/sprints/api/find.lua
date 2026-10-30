-- Finding items by number or words. Zoho has no project-wide item search that works for us
-- (orgitemlogs 7500s, project-level itemcountandepoint 7404s, the release list needs an OAuth
-- scope we don't have), but each sprint's item list takes a search. So: search sprint by
-- sprint, most likely first, a few at a time, and remember where items were found.
--
-- Search request, confirmed against real EU responses:
--   GET /team/{t}/projects/{p}/sprints/{s}/item/?action=data&viewtype=1&searchby=both
--       &searchvalue=22516&subitem=true&index=1&range=25
-- searchby=both matches the item number (digits only: "22516", not "CV-I22516") and the title.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local items = require("sprints.api.items")
local sprints = require("sprints.api.sprints")
local workspace = require("sprints.api.workspace")

local M = {}

M.CONCURRENCY = 6
M.SEARCH = { action = "data", viewtype = 1, searchby = "both", subitem = "true", range = 25 }

--- "CV-I22516", "I22516", "#22516", "22516" -> "22516". nil when there are no digits.
--- The API's itemNo is the bare number; "CV-" and "I" are display only. Pure.
function M.item_number(wanted)
  return wanted and tostring(wanted):match("(%d+)%s*$") or nil
end

--- Sprint ids in search order: `first` (a cached location) if given, then active sprints,
--- the backlog, upcoming, then completed/cancelled newest first. No duplicates. Pure.
---@param list table[] sprints as from sprints.list (already sorted by sprints.sort)
---@param backlog string|nil
---@param first string|nil
---@param scope "all"|"open" open = skip completed and cancelled sprints
function M.order(list, backlog, first, scope)
  local out, seen = {}, {}
  local function add(id)
    if id and not seen[tostring(id)] then
      seen[tostring(id)] = true
      table.insert(out, tostring(id))
    end
  end
  add(first)
  for _, s in ipairs(list) do
    if s.state == "active" then
      add(s.id)
    end
  end
  add(backlog)
  for _, s in ipairs(list) do
    local closed = s.state == "completed" or s.state == "cancelled"
    if scope == "all" or not closed then
      add(s.id)
    end
  end
  return out
end

--- Run worker(id, done) over ids, at most `n` in flight. done(value, err).
--- mode "first": stop at the first non-nil value and cb(value).
--- mode "all":   cb(list of every non-nil value, in id order).
--- A failing id doesn't stop the run; cb's second arg is the error count, third the first error.
---@param on_progress fun(finished: integer, total: integer)|nil
function M.run(ids, n, mode, worker, cb, on_progress)
  local total, next_i, in_flight, finished, stopped = #ids, 1, 0, 0, false
  local results, errors, first_err = {}, 0, nil

  local function finish(value)
    stopped = true
    if mode == "first" then
      return cb(value, errors, first_err)
    end
    local out = {}
    for i = 1, total do
      if results[i] ~= nil then
        table.insert(out, results[i])
      end
    end
    cb(out, errors, first_err)
  end

  if total == 0 then
    return vim.schedule(function()
      finish(nil)
    end)
  end

  local launch
  local function on_done(i, value, err)
    if stopped then
      return
    end
    in_flight, finished = in_flight - 1, finished + 1
    if err then
      errors, first_err = errors + 1, first_err or err
    elseif value ~= nil then
      if mode == "first" then
        return finish(value)
      end
      results[i] = value
    end
    if on_progress then
      on_progress(finished, total)
    end
    if finished == total then
      return finish(nil)
    end
    launch()
  end

  launch = function()
    while not stopped and in_flight < n and next_i <= total do
      local i = next_i
      next_i, in_flight = next_i + 1, in_flight + 1
      worker(ids[i], function(value, err)
        on_done(i, value, err)
      end)
    end
  end
  launch()
end

--- Search one sprint (or the backlog). cb(items) — normalised, like items.list.
---@param all_pages boolean false = first page only (enough for an item number)
function M.in_sprint(ref, value, meta, all_pages, cb)
  local path = ("/team/%s/projects/%s/sprints/%s/item/"):format(ref.team, ref.project, ref.sprint)
  local query = vim.tbl_extend("force", {}, M.SEARCH, { searchvalue = value })
  local function decode(bodies)
    local rows, side = async.merge(bodies, "item")
    local out = {}
    for _, r in ipairs(rows) do
      table.insert(out, items.normalise(r, ref, meta, side))
    end
    return out
  end
  if all_pages then
    return async.pages(path, query, "item", function(bodies, err)
      cb(bodies and decode(bodies) or nil, err)
    end)
  end
  client.request("GET", path, { query = vim.tbl_extend("force", query, { index = 1 }) }, function(result, err)
    cb(result and decode({ result.body or {} }) or nil, err)
  end)
end

-- On-disk cache: "team/project" -> { item number -> sprint id }. Only the sprint is cached,
-- and it's searched first rather than trusted: items move between sprints, and a stale
-- entry then costs one extra request instead of a broken :SprintsItem.
local cache_data

function M.cache_path()
  return vim.fn.stdpath("cache") .. "/sprints.nvim/item_sprints.json"
end

local function cache_load()
  if cache_data then
    return cache_data
  end
  cache_data = {}
  local f = io.open(M.cache_path(), "r")
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(decoded) == "table" then
      cache_data = decoded
    end
  end
  return cache_data
end

function M.cache_get(team, project, no)
  return (cache_load()[team .. "/" .. project] or {})[tostring(no)]
end

function M.cache_put(team, project, no, sprint)
  local data, key = cache_load(), team .. "/" .. project
  data[key] = data[key] or {}
  if data[key][tostring(no)] == tostring(sprint) then
    return
  end
  data[key][tostring(no)] = tostring(sprint)
  vim.fn.mkdir(vim.fn.fnamemodify(M.cache_path(), ":h"), "p")
  local f = io.open(M.cache_path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- Test hook: forget the in-memory copy (the next call re-reads the file).
function M.cache_reset()
  cache_data = nil
end

--- Sprint list + backlog + project meta, which every search needs.
local function prepare(team, project, cb)
  async.all({
    function(done)
      sprints.list(team, project, done)
    end,
    function(done)
      sprints.backlog_id(team, project, function(id)
        done(id or false, nil) -- a missing backlog shouldn't block the search
      end)
    end,
    function(done)
      workspace.meta(team, project, done)
    end,
  }, function(res, err)
    if not res then
      return cb(nil, err)
    end
    cb({ list = res[1], backlog = res[2] or nil, meta = res[3] }, nil)
  end)
end

local function failure_note(errors, total, first_err)
  if errors == 0 then
    return nil
  end
  return ("%d of %d sprint searches failed (%s)"):format(errors, total, first_err and first_err.message or "?")
end

--- Find one item by number in a project. cb(item, note) or cb(nil, err).
--- item is normalised (item.ref opens it); note mentions failed sprint searches, if any.
---@param on_progress fun(done: integer, total: integer)|nil
function M.item(team, project, wanted, cb, on_progress)
  local no = M.item_number(wanted)
  if not no then
    return async.fail(cb, ("%q has no item number in it"):format(wanted))
  end
  prepare(team, project, function(ctx, err)
    if not ctx then
      return cb(nil, err)
    end
    local ids = M.order(ctx.list, ctx.backlog, M.cache_get(team, project, no), "all")
    M.run(ids, M.CONCURRENCY, "first", function(sprint, done)
      M.in_sprint({ team = team, project = project, sprint = sprint }, no, ctx.meta, false, function(found, serr)
        if not found then
          return done(nil, serr)
        end
        for _, it in ipairs(found) do
          if M.item_number(it.no) == no then
            return done(it, nil)
          end
        end
        done(nil, nil)
      end)
    end, function(it, errors, first_err)
      local note = failure_note(errors, #ids, first_err)
      if it then
        M.cache_put(team, project, no, it.ref.sprint)
        return cb(it, note)
      end
      if errors == #ids and errors > 0 then
        return cb(nil, first_err) -- every request failed: that's an error, not "not found"
      end
      cb(nil, { message = ("%s not found in %d sprints%s"):format(wanted, #ids, note and ("; " .. note) or "") })
    end, on_progress)
  end)
end

--- Items matching `query` (number or title words) across sprints. Duplicates (an item seen
--- via more than one sprint) are dropped. cb(items, note) or cb(nil, err).
---@param scope "all"|"open"
function M.search(team, project, query, scope, cb, on_progress)
  prepare(team, project, function(ctx, err)
    if not ctx then
      return cb(nil, err)
    end
    local ids = M.order(ctx.list, ctx.backlog, nil, scope)
    M.run(ids, M.CONCURRENCY, "all", function(sprint, done)
      M.in_sprint({ team = team, project = project, sprint = sprint }, query, ctx.meta, true, function(found, serr)
        done(found and #found > 0 and found or nil, serr)
      end)
    end, function(lists, errors, first_err)
      if errors == #ids and errors > 0 then
        return cb(nil, first_err)
      end
      local out, seen = {}, {}
      for _, list in ipairs(lists) do
        for _, it in ipairs(list) do
          if not seen[it.id] then
            seen[it.id] = true
            table.insert(out, it)
          end
        end
      end
      cb(out, failure_note(errors, #ids, first_err))
    end, on_progress)
  end)
end

return M
