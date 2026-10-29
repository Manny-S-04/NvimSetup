local config = require("sprints.config")

local M = {}

local function api(name)
  return require("sprints.api." .. name)
end

local function notify_error(prefix, err)
  require("sprints.ui.util").notify_error(prefix, err)
end

--- Items of several sprints, concatenated; only `me`'s when mine_only.
local function items_of(team, project, sprint_ids, mine_only, cb)
  local async = api("async")
  local function run(me)
    local fns = {}
    for _, sid in ipairs(sprint_ids) do
      table.insert(fns, function(done)
        local ref = { team = team, project = project, sprint = sid }
        if me then
          api("items").list_owned(ref, me, done)
        else
          api("items").list(ref, done)
        end
      end)
    end
    async.all(fns, function(lists, err)
      if not lists then
        return cb(nil, err)
      end
      local out = {}
      for _, l in ipairs(lists) do
        vim.list_extend(out, l)
      end
      cb(out, nil)
    end)
  end
  if not mine_only then
    return run(nil)
  end
  api("workspace").me(team, project, function(me, err)
    if not me then
      return cb(nil, err)
    end
    run(me)
  end)
end

--- Fetcher for the list buffer: the active sprint(s) of the project.
local function active_fetcher(team, project)
  return function(mine_only, cb)
    api("sprints").active(team, project, function(active, err)
      if not active then
        return cb(nil, err)
      end
      if #active == 0 then
        return cb(nil, { message = "no active sprint in this project (try :SprintsSprint pick)" })
      end
      local ids, names = {}, {}
      for _, s in ipairs(active) do
        table.insert(ids, s.id)
        table.insert(names, s.name)
      end
      items_of(team, project, ids, mine_only, function(list, ierr)
        cb(list, ierr, table.concat(names, " + "))
      end)
    end)
  end
end

local function open_active(mine_only)
  require("sprints.ui.context").project(function(team, project)
    require("sprints.ui.list").open_with("active/" .. project, "Active sprint", active_fetcher(team, project),
      { mine_only = mine_only })
  end)
end

local function open_sprint(team, project, sprint)
  require("sprints.ui.list").open_with("sprint/" .. sprint.id, sprint.name, function(mine_only, cb)
    items_of(team, project, { sprint.id }, mine_only, cb)
  end)
end

local function cmd_sprint(cmd_opts)
  local arg = vim.trim(cmd_opts.args or "")
  if arg == "" then
    return open_active(false)
  end
  if arg ~= "pick" then
    return vim.notify("sprints.nvim: usage :SprintsSprint [pick]", vim.log.levels.WARN)
  end
  require("sprints.ui.context").project(function(team, project)
    api("sprints").list(team, project, function(list, err)
      if not list then
        return notify_error("could not list sprints", err)
      end
      if #list == 0 then
        return vim.notify("sprints.nvim: this project has no sprints", vim.log.levels.WARN)
      end
      vim.ui.select(list, {
        prompt = "Sprint",
        format_item = function(s)
          return ("%s  [%s]"):format(s.name, s.state or "?")
        end,
      }, function(choice)
        if choice then
          open_sprint(team, project, choice)
        end
      end)
    end)
  end)
end

local function cmd_backlog()
  require("sprints.ui.context").project(function(team, project)
    api("sprints").backlog_id(team, project, function(id, err)
      if not id then
        return notify_error("could not find the backlog", err)
      end
      open_sprint(team, project, { id = id, name = "Backlog" })
    end)
  end)
end

--- Item reference in a word like "PRJ-I12,", "(I12)", "#12" or "12"; nil if there's none.
function M.ref_in_word(word)
  return word:match("[%w%-]*%d+")
end

--- Does `wanted` (as typed: "I12", "PRJ-I12", "#12", "12") name this item?
--- A bare number matches the item whose key/number ends in exactly those digits.
function M.item_matches(it, wanted)
  local w = wanted:upper():gsub("^#", "")
  local key, no = (it.key or ""):upper(), tostring(it.no or ""):upper()
  if w == key or w == no then
    return true
  end
  if w:match("^%d+$") then
    return key:match("(%d+)$") == w or no:match("(%d+)$") == w
  end
  local suffix = "%-" .. vim.pesc(w) .. "$"
  return key:match(suffix) ~= nil or no:match(suffix) ~= nil
end

--- :SprintsItem I123 — search the active sprint(s) and the backlog for that item number.
--- (Zoho has no "get item by number" call, so this is a scan.)
local function cmd_item(cmd_opts)
  local wanted = vim.trim(cmd_opts.args or "")
  if wanted == "" then
    wanted = M.ref_in_word(vim.fn.expand("<cWORD>")) or ""
  end
  if wanted == "" then
    return vim.notify("sprints.nvim: usage :SprintsItem <item number> (or cursor on one)", vim.log.levels.WARN)
  end
  require("sprints.ui.context").project(function(team, project)
    local async = api("async")
    async.all({
      function(done)
        api("sprints").active(team, project, done)
      end,
      function(done)
        api("sprints").backlog_id(team, project, function(id)
          done(id or false, nil) -- a missing backlog shouldn't block the sprint search
        end)
      end,
    }, function(res, err)
      if not res then
        return notify_error("could not search", err)
      end
      local ids = {}
      for _, s in ipairs(res[1]) do
        table.insert(ids, s.id)
      end
      if res[2] then
        table.insert(ids, res[2])
      end
      items_of(team, project, ids, false, function(list, ierr)
        if not list then
          return notify_error("could not search", ierr)
        end
        for _, it in ipairs(list) do
          if M.item_matches(it, wanted) then
            return require("sprints.ui.item").open_ref(it.ref, it.key)
          end
        end
        vim.notify(("sprints.nvim: %s not found in the active sprint(s) or backlog"):format(wanted), vim.log.levels.WARN)
      end)
    end)
  end)
end

--- :SprintsRaw <what> — raw API responses, for checking the field mapping.
local RAW = {
  teams = function(_, _, cb)
    api("client").request("GET", "/teams/", {}, cb)
  end,
  projects = function(team, _, cb)
    api("client").request("GET", ("/team/%s/projects/"):format(team), { query = { action = "allprojects", index = 1, range = 10 } }, cb)
  end,
  project = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/"):format(team, project), { query = { action = "details" } }, cb)
  end,
  sprints = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/sprints/"):format(team, project), { query = { action = "data", index = 1, range = 10 } }, cb)
  end,
  statuses = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/itemstatus/"):format(team, project), { query = { action = "data" } }, cb)
  end,
  users = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/users/"):format(team, project), { query = { action = "data", index = 1, range = 10 } }, cb)
  end,
}

local function cmd_raw(cmd_opts)
  local what = vim.trim(cmd_opts.args or "")
  local fn = RAW[what]
  if not fn then
    return vim.notify("sprints.nvim: usage :SprintsRaw " .. table.concat(vim.tbl_keys(RAW), "|"), vim.log.levels.WARN)
  end
  local function go(team, project)
    fn(team, project, function(result, err)
      require("sprints.ui.item").show_value("sprints://raw/" .. what, result and result.body or { error = err })
    end)
  end
  if what == "teams" then
    return go(nil, nil)
  end
  require("sprints.ui.context").project(go)
end

local function cmd_help()
  local o = config.options
  vim.notify(table.concat({
    "sprints.nvim (Zoho Sprints)",
    "",
    "  :SprintsMine            Your items in the active sprint(s)",
    "  :SprintsSprint [pick]   Active sprint(s); pick = choose any sprint",
    "  :SprintsBacklog         The project backlog",
    "  :SprintsItem [NO]       Open an item by number (defaults to the word under the cursor)",
    "  :SprintsProject         Switch project for this session",
    "  :SprintsRefresh         Refresh the current item buffer",
    "  :SprintsRaw <what>      Raw API response (teams|projects|project|sprints|statuses|users)",
    "",
    "In a list: <CR> open, m toggle mine, r refresh. In an item: g? for keys.",
    "",
    ("Data centre: zoho.%s   team: %s   project: %s"):format(config.domain(), o.team_id or "(pick)", o.project_id or "(pick)"),
  }, "\n"))
end

local function guarded(fn)
  return function(cmd_opts)
    if config.validate() then
      fn(cmd_opts or {})
    end
  end
end

local COMMANDS = {
  { "Sprints", cmd_help, { nargs = 0, desc = "sprints.nvim help" }, false },
  { "SprintsMine", function() open_active(true) end, { nargs = 0, desc = "Your items in the active sprint" } },
  { "SprintsSprint", cmd_sprint, {
    nargs = "?",
    complete = function()
      return { "pick" }
    end,
    desc = "Items in the active sprint (or pick one)",
  } },
  { "SprintsBacklog", cmd_backlog, { nargs = 0, desc = "Items in the project backlog" } },
  { "SprintsItem", cmd_item, { nargs = "?", desc = "Open a Zoho Sprints item by number" } },
  { "SprintsProject", function()
    require("sprints.ui.context").project(function(_, project)
      vim.notify("sprints.nvim: project " .. project .. " for this session")
    end, true)
  end, { nargs = 0, desc = "Switch Zoho Sprints project" } },
  { "SprintsRefresh", function()
    require("sprints.ui.item").refresh(vim.api.nvim_get_current_buf())
  end, { nargs = 0, desc = "Refresh the current item buffer" } },
  { "SprintsRaw", cmd_raw, {
    nargs = 1,
    complete = function()
      return vim.tbl_keys(RAW)
    end,
    desc = "Show a raw Zoho Sprints API response",
  } },
}
M.NAMES = vim.tbl_map(function(c)
  return c[1]
end, COMMANDS)

function M.setup()
  for _, c in ipairs(COMMANDS) do
    local fn = c[4] == false and c[2] or guarded(c[2])
    vim.api.nvim_create_user_command(c[1], fn, c[3])
  end
end

return M
