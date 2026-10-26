-- Worklist: a Harpoon list of tickets you're working through, typically a parent's children.
--
--   :JiraWork [KEY]        KEY's parent's children become the worklist (no parent: KEY's own children)
--   :JiraWorklist          open it (Harpoon's quick menu: reorder/delete lines like any harpoon list)
--   :JiraWorklist refresh  re-fetch statuses/summaries
--   next / prev            jira.worklist.next() / .prev() (map them, e.g. <leader>jn / <leader>jp)
--
-- Lives in Harpoon (list "jira", per cwd like your file list) so it survives restarts and uses
-- the menu you already know. Harpoon is optional: without it these commands just say so.
local M = {}

M.LIST = "jira"

-- ── pure helpers (unit-tested) ──────────────────────────────────────────────────────────
local KEY = "[A-Za-z][A-Za-z0-9_]*%-%d+"

function M.is_done(ctx)
  return ctx and (ctx.status_category == "done" or (ctx.status or ""):lower() == "done")
end

--- One worklist line: "CV-123  [In Progress] Fix the thing". The key comes first so a line
--- edited in Harpoon's menu can always be parsed back.
function M.format_item(item)
  local ctx = item.context or {}
  local status = ctx.status and ("[" .. ctx.status .. "] ") or ""
  local mark = M.is_done(ctx) and "✓ " or ""
  return vim.trim(("%s  %s%s%s"):format(item.value, mark, status, ctx.summary or ""))
end

--- Key from a menu line (or a bare key), or nil.
function M.parse_line(line)
  if type(line) ~= "string" then return nil end
  local key = vim.trim(line):match("^(" .. KEY .. ")")
  return key and key:upper() or nil
end

function M.item_for(issue)
  return {
    value = issue.key,
    context = {
      summary = issue.summary,
      status = issue.status,
      status_category = issue.status_category,
      issue_type = issue.issue_type,
    },
  }
end

-- ── harpoon wiring ──────────────────────────────────────────────────────────────────────
local cache = {} -- key -> context, so a line edited in the menu keeps its summary/status

local function current_key()
  local key = vim.b.jira_issue_key
  if key then return key end
  local lk = vim.b.jira_list_keys
  if lk then return lk[tostring(vim.api.nvim_win_get_cursor(0)[1])] end
  return M.parse_line(vim.fn.expand("<cWORD>"):match(KEY) or "")
end

local list_config = {
  encode = function(item) return vim.json.encode(item) end,
  decode = function(s) return vim.json.decode(s) end,
  display = function(item) return M.format_item(item) end,
  equals = function(a, b)
    if a == nil or b == nil then return a == b end
    return a.value == b.value
  end,
  create_list_item = function(_, item)
    if type(item) == "table" then return item end
    local key = M.parse_line(item) or (item == nil and current_key()) or nil
    if not key then return nil end
    return { value = key, context = cache[key] or {} }
  end,
  select = function(item)
    if item and item.value then
      require("jira.ui.issue").open_key(item.value, { reuse_window = true })
    end
  end,
  -- the default BufLeave records cursor positions for *files*; these items aren't files
  BufLeave = function() end,
}

local function harpoon()
  local ok, h = pcall(require, "harpoon")
  if not ok or type(h) ~= "table" or not h.list then
    vim.notify("jira.nvim: the worklist needs ThePrimeagen/harpoon (branch harpoon2)", vim.log.levels.WARN)
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

--- Replace the worklist with `issues`.
function M.set(issues, title)
  local list, h = M.list()
  if not list then return end
  if list:length() > 0 then
    local choice = vim.fn.confirm(("Replace the current worklist (%d tickets)?"):format(list:length()), "&Yes\n&No", 1)
    if choice ~= 1 then return end
  end
  list:clear()
  for _, issue in ipairs(issues) do
    local item = M.item_for(issue)
    cache[item.value] = item.context
    list:add(item)
  end
  h:sync()
  vim.notify(("jira.nvim: worklist = %d tickets%s"):format(#issues, title and (" from " .. title) or ""))
  M.open()
end

--- Add one issue (or the one under the cursor / in this buffer).
function M.add(issue)
  local list, h = M.list()
  if not list then return end
  local item
  if issue then
    item = M.item_for(issue)
  else
    local key = current_key()
    if not key then return vim.notify("jira.nvim: no issue here to add", vim.log.levels.WARN) end
    item = { value = key, context = cache[key] or {} }
  end
  cache[item.value] = item.context
  list:add(item)
  h:sync()
  vim.notify("jira.nvim: added " .. item.value .. " to the worklist")
end

function M.open()
  local list, h = M.list()
  if not list then return end
  h.ui:toggle_quick_menu(list, { title = " Jira worklist " })
end

function M.next()
  local list = M.list()
  if list then list:next({ ui_nav_wrap = true }) end
end

function M.prev()
  local list = M.list()
  if list then list:prev({ ui_nav_wrap = true }) end
end

--- Keep an item's status/summary current when its issue is (re)loaded anywhere in jira.nvim.
--- Only if the worklist is already in use: never loads Harpoon just for this.
function M.update(issue)
  if not (package.loaded["harpoon"] and issue and issue.key) then return end
  local ok, h = pcall(require, "harpoon")
  if not ok or not h.config[M.LIST] then return end
  local list = h:list(M.LIST)
  for _, item in ipairs(list.items) do
    if item and item.value == issue.key then
      item.context = M.item_for(issue).context
      cache[issue.key] = item.context
      h:sync()
      return
    end
  end
end

--- Re-fetch every ticket's status and summary.
function M.refresh()
  local list, h = M.list()
  if not list then return end
  local keys = {}
  for _, item in ipairs(list.items) do
    if item and item.value then table.insert(keys, item.value) end
  end
  if #keys == 0 then return vim.notify("jira.nvim: the worklist is empty") end
  require("jira.api.issues").search(("key in (%s)"):format(table.concat(keys, ",")), function(found, err)
    if not found then return require("jira.ui.util").notify_error("worklist refresh failed", err) end
    for _, issue in ipairs(found) do M.update(issue) end
    local done = 0
    for _, item in ipairs(list.items) do
      if item and M.is_done(item.context) then done = done + 1 end
    end
    h:sync()
    vim.notify(("jira.nvim: worklist refreshed — %d/%d done"):format(done, #keys))
  end)
end

-- ── the main flow ───────────────────────────────────────────────────────────────────────
--- "I was given KEY; its parent has the tickets I'm meant to do."
function M.work(key)
  local hierarchy = require("jira.api.hierarchy")
  local util = require("jira.ui.util")
  vim.notify("jira.nvim: finding " .. key .. "'s parent…")
  hierarchy.parent(key, function(parent, err)
    if err then return util.notify_error("could not read " .. key, err) end
    local root = parent and parent.key or key
    hierarchy.children(root, function(children, cerr)
      if not children then return util.notify_error("could not list " .. root .. "'s children", cerr) end
      if #children == 0 then
        return vim.notify(("jira.nvim: %s has no parent and no child tickets"):format(key), vim.log.levels.WARN)
      end
      local title = root .. (parent and parent.summary and (" " .. parent.summary) or "")
      M.set(children, title)
    end)
  end)
end

return M
