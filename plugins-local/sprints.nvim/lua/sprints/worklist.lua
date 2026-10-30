-- Worklist: a Harpoon list of items you're working through, typically a parent's sub items.
-- Ported from jira.nvim's worklist.
--
--   :SprintsWork [KEY]        KEY's parent's sub items become the worklist (no parent: KEY's own)
--   :SprintsWorklist          open it (Harpoon's quick menu: reorder/delete lines like any list)
--   :SprintsWorklist refresh  re-fetch statuses/summaries
--   next / prev               sprints.worklist.next() / .prev()
--
-- Lives in Harpoon (list "sprints", per cwd like your file list) so it survives restarts. Each
-- entry keeps the item's ref (its four ids), so selecting one opens it without a search.
local M = {}

M.LIST = "sprints"

-- ── pure helpers (unit-tested) ──────────────────────────────────────────────────────────
local KEY = "[%w%-#]*%d+"

function M.is_done(ctx)
  return ctx ~= nil and (ctx.status_category == "done" or (ctx.status or ""):lower() == "done")
end

--- One worklist line: "I123  [In Progress] Fix the thing". The key comes first so a line
--- edited in Harpoon's menu can always be parsed back.
function M.format_item(item)
  local ctx = item.context or {}
  local status = ctx.status and ("[" .. ctx.status .. "] ") or ""
  local mark = M.is_done(ctx) and "✓ " or ""
  return vim.trim(("%s  %s%s%s"):format(item.value, mark, status, ctx.summary or ""))
end

--- Key from a menu line (or a bare key), or nil.
function M.parse_line(line)
  if type(line) ~= "string" then
    return nil
  end
  local key = vim.trim(line):match("^(" .. KEY .. ")")
  return key and key:upper() or nil
end

--- Harpoon item for a normalised Sprints item.
function M.item_for(it)
  return {
    value = it.key,
    context = {
      summary = it.summary,
      status = it.status,
      status_category = it.status_category,
      issue_type = it.issue_type,
      ref = it.ref,
    },
  }
end

-- ── harpoon wiring ──────────────────────────────────────────────────────────────────────
local cache = {} -- key -> context, so a line edited in the menu keeps its summary/status/ref

--- The item in this buffer, or under the cursor in a list.
local function current()
  local it = require("sprints.ui.item").item_of(0)
  if it then
    return it
  end
  if vim.bo.filetype == "sprints-list" then
    return require("sprints.ui.list").item_under_cursor(0)
  end
  return nil
end

local function open_entry(item)
  local ctx = item.context or {}
  if ctx.ref and ctx.ref.item then
    return require("sprints.ui.item").open_ref(ctx.ref, item.value, { reuse_window = true })
  end
  -- typed into the menu by hand: no ids yet, find it by number
  require("sprints.ui.context").project(function(team, project)
    require("sprints.api.find").item(team, project, item.value, function(it, err)
      if not it then
        return require("sprints.ui.util").notify_error("could not find " .. item.value, err)
      end
      cache[item.value] = M.item_for(it).context
      item.context = cache[item.value]
      require("sprints.ui.item").open_ref(it.ref, it.key, { reuse_window = true })
    end)
  end)
end

local list_config = {
  encode = function(item)
    return vim.json.encode(item)
  end,
  decode = function(s)
    return vim.json.decode(s)
  end,
  display = function(item)
    return M.format_item(item)
  end,
  equals = function(a, b)
    if a == nil or b == nil then
      return a == b
    end
    return a.value == b.value
  end,
  create_list_item = function(_, item)
    if type(item) == "table" then
      return item
    end
    local key = M.parse_line(item)
    if not key and item == nil then
      local it = current()
      if it then
        return M.item_for(it)
      end
    end
    if not key then
      return nil
    end
    return { value = key, context = cache[key] or {} }
  end,
  select = function(item)
    if item and item.value then
      open_entry(item)
    end
  end,
  -- the default BufLeave records cursor positions for *files*; these items aren't files
  BufLeave = function() end,
}

local function harpoon()
  local ok, h = pcall(require, "harpoon")
  if not ok or type(h) ~= "table" or not h.list then
    vim.notify("sprints.nvim: the worklist needs ThePrimeagen/harpoon (branch harpoon2)", vim.log.levels.WARN)
    return nil
  end
  -- Register our list type before its first use. Direct assignment rather than a second
  -- harpoon:setup(), which would rebuild Harpoon's data store under the user's file lists.
  h.config[M.LIST] = vim.tbl_extend("force", h.config[M.LIST] or {}, list_config)
  return h
end

function M.list()
  local h = harpoon()
  return h and h:list(M.LIST), h
end

--- Replace the worklist with `items` (normalised Sprints items).
function M.set(items, title)
  local list, h = M.list()
  if not list then
    return
  end
  if list:length() > 0 then
    local choice = vim.fn.confirm(("Replace the current worklist (%d items)?"):format(list:length()), "&Yes\n&No", 1)
    if choice ~= 1 then
      return
    end
  end
  list:clear()
  for _, it in ipairs(items) do
    local entry = M.item_for(it)
    cache[entry.value] = entry.context
    list:add(entry)
  end
  h:sync()
  vim.notify(("sprints.nvim: worklist = %d items%s"):format(#items, title and (" from " .. title) or ""))
  M.open()
end

--- Add one item (or the one in this buffer / under the cursor in a list).
function M.add(it)
  local list, h = M.list()
  if not list then
    return
  end
  it = it or current()
  if not it then
    return vim.notify("sprints.nvim: no item here to add", vim.log.levels.WARN)
  end
  local entry = M.item_for(it)
  cache[entry.value] = entry.context
  list:add(entry)
  h:sync()
  vim.notify("sprints.nvim: added " .. entry.value .. " to the worklist")
end

function M.open()
  local list, h = M.list()
  if list then
    h.ui:toggle_quick_menu(list, { title = " Sprints worklist " })
  end
end

function M.next()
  local list = M.list()
  if list then
    list:next({ ui_nav_wrap = true })
  end
end

function M.prev()
  local list = M.list()
  if list then
    list:prev({ ui_nav_wrap = true })
  end
end

--- Keep an entry's status/summary current when its item is (re)loaded anywhere in sprints.nvim.
--- Only if the worklist is already in use: never loads Harpoon just for this.
---@return boolean changed
function M.update(it)
  if not (package.loaded["harpoon"] and it and it.key) then
    return false
  end
  local ok, h = pcall(require, "harpoon")
  if not ok or not h.config[M.LIST] then
    return false
  end
  for _, entry in ipairs(h:list(M.LIST).items) do
    if entry and entry.value == it.key then
      entry.context = M.item_for(it).context
      cache[it.key] = entry.context
      h:sync()
      return true
    end
  end
  return false
end

--- Sprint refs to list so every entry's status can be refreshed: one per distinct sprint. Pure.
---@param entries table[] harpoon items
---@return table[] refs { team, project, sprint }
---@return string[] keys entries with no ref (typed by hand), which can't be refreshed this way
function M.sprints_of(entries)
  local refs, seen, missing = {}, {}, {}
  for _, e in ipairs(entries) do
    local ref = e and e.context and e.context.ref
    if ref and ref.sprint then
      local id = ref.team .. "/" .. ref.project .. "/" .. ref.sprint
      if not seen[id] then
        seen[id] = true
        table.insert(refs, { team = ref.team, project = ref.project, sprint = ref.sprint })
      end
    elseif e and e.value then
      table.insert(missing, e.value)
    end
  end
  return refs, missing
end

--- Re-fetch every entry's status and summary: one list request per sprint involved.
function M.refresh()
  local list, h = M.list()
  if not list then
    return
  end
  local entries = vim.tbl_filter(function(e)
    return e ~= nil and e.value ~= nil
  end, list.items)
  if #entries == 0 then
    return vim.notify("sprints.nvim: the worklist is empty")
  end
  local refs, missing = M.sprints_of(entries)
  local items_api = require("sprints.api.items")
  local fns = vim.tbl_map(function(ref)
    return function(done)
      items_api.list(ref, done)
    end
  end, refs)
  require("sprints.api.async").all(fns, function(lists, err)
    if not lists then
      return require("sprints.ui.util").notify_error("worklist refresh failed", err)
    end
    for _, rows in ipairs(lists) do
      for _, it in ipairs(rows) do
        M.update(it)
      end
    end
    local done = 0
    for _, e in ipairs(entries) do
      if M.is_done(e.context) then
        done = done + 1
      end
    end
    h:sync()
    local note = #missing > 0 and (" (not refreshed, open them once: " .. table.concat(missing, ", ") .. ")") or ""
    vim.notify(("sprints.nvim: worklist refreshed — %d/%d done%s"):format(done, #entries, note))
  end)
end

-- ── the main flow ───────────────────────────────────────────────────────────────────────
--- "I was given this item; its parent has the items I'm meant to do."
---@param it table normalised item
function M.work(it)
  local hierarchy = require("sprints.api.hierarchy")
  local util = require("sprints.ui.util")
  vim.notify("sprints.nvim: finding " .. it.key .. "'s parent…")
  hierarchy.parent(it, function(parent, err)
    if err then
      return util.notify_error("could not read " .. it.key .. "'s parent", err)
    end
    local root = parent or it
    hierarchy.children(root, function(children, cerr)
      if not children then
        return util.notify_error("could not list " .. root.key .. "'s sub items", cerr)
      end
      if #children == 0 then
        return vim.notify(("sprints.nvim: %s has no parent and no sub items"):format(it.key), vim.log.levels.WARN)
      end
      M.set(children, root.key .. (parent and parent.summary and (" " .. parent.summary) or ""))
    end)
  end)
end

return M
