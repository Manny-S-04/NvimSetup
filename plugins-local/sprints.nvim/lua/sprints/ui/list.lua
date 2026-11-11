-- Item list buffer (a sprint, the backlog, search results). Ported from jira.nvim's list.
-- `b` toggles a board view (grouped by status), `m` toggles only-mine.
local render = require("sprints.ui.render")
local util = require("sprints.ui.util")

local M = {}

-- bufnr -> { fetch, mine_only, group, project = {team, project}, new_target, by_line, shown, generation }
-- (functions and item tables can't live in vim.b)
local state = {}

local function item_under_cursor(bufnr)
  local s = state[bufnr]
  return s and s.by_line[vim.api.nvim_win_get_cursor(0)[1]] or nil
end

--- The item on the cursor line of a list buffer (0 = current), or nil.
function M.item_under_cursor(bufnr)
  return item_under_cursor(bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
end

local function first_item_line(by_line)
  local first = nil
  for line in pairs(by_line) do
    first = (not first or line < first) and line or first
  end
  return first
end

--- Re-render from the last fetch (toggling the board view needs no request).
local function draw(bufnr, status_order)
  local s = state[bufnr]
  local title = vim.b[bufnr].sprints_list_title .. (s.mine_only and " (mine)" or "")
  local lines, highlights, by_line = render.render_list(title, s.shown, { group = s.group, status_order = status_order })
  -- keep the cursor on the same item across redraws
  local before = item_under_cursor(bufnr)
  s.by_line = by_line
  util.set_lines(bufnr, lines)
  util.apply_highlights(bufnr, highlights)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end
  local target = first_item_line(by_line)
  for line, it in pairs(by_line) do
    if before and it.id == before.id then
      target = line
    end
  end
  if target then
    pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
  end
end

local function with_status_order(bufnr, cb)
  local s = state[bufnr]
  if not (s.group and s.project) then
    return cb(nil)
  end
  require("sprints.api.workspace").meta(s.project.team, s.project.project, function(meta)
    cb(meta and meta.status_order or nil)
  end)
end

local function load(bufnr)
  local s = state[bufnr]
  local title = vim.b[bufnr].sprints_list_title
  util.set_lines(bufnr, { "# " .. title, "", "Loading…" })

  -- Only the latest load may render: a slower, older response (r or m pressed mid-load,
  -- or the list reopened) would otherwise overwrite the newer one.
  s.generation = (s.generation or 0) + 1
  local generation = s.generation

  s.fetch(s.mine_only, function(results, err, new_title)
    if not vim.api.nvim_buf_is_valid(bufnr) or state[bufnr] ~= s or s.generation ~= generation then
      return
    end
    if new_title then
      title = new_title
      vim.b[bufnr].sprints_list_title = new_title
    end
    if not results then
      util.set_lines(bufnr, { "# " .. title, "", "Error: " .. (err and err.message or "unknown error"), "", "r to retry" })
      return util.notify_error("loading items failed", err)
    end
    s.shown = results
    with_status_order(bufnr, function(order)
      if vim.api.nvim_buf_is_valid(bufnr) and s.generation == generation then
        draw(bufnr, order)
      end
    end)
  end)
end

local HELP = {
  { "open", "open item" },
  { "new", "new item in this sprint (:w creates)" },
  { "board", "toggle board view (grouped by status)" },
  { "mine", "toggle only my items" },
  { "yank_key", "copy the item key" },
  { "yank_url", "copy the link" },
  { "browser", "open in browser" },
  { "worklist", "make this list the worklist" },
  { "worklist_add", "add item to the worklist" },
  { "refresh", "refresh" },
  { "close", "close" },
}

local function setup_keymaps(bufnr)
  local keys = (require("sprints.config").options.keymaps or {}).list or {}
  local items_api = require("sprints.api.items")
  local function map(name, fn)
    if keys[name] then
      local desc = name
      for _, h in ipairs(HELP) do
        if h[1] == name then
          desc = h[2]
        end
      end
      vim.keymap.set("n", keys[name], fn, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: " .. desc })
    end
  end
  local function on_item(fn)
    return function()
      local it = item_under_cursor(bufnr)
      if it then
        fn(it)
      end
    end
  end
  map("open", on_item(function(it)
    require("sprints.ui.item").open_ref(it.ref, it.key)
  end))
  map("browser", on_item(function(it)
    vim.ui.open(items_api.browse_url(it.ref, it.no))
  end))
  map("yank_key", on_item(function(it)
    util.yank(it.key, "key")
  end))
  map("yank_url", on_item(function(it)
    util.yank(items_api.browse_url(it.ref, it.no), "link")
  end))
  map("refresh", function()
    load(bufnr)
  end)
  map("worklist", function()
    local shown = state[bufnr].shown
    if shown and #shown > 0 then
      require("sprints.worklist").set(shown, vim.b[bufnr].sprints_list_title)
    end
  end)
  map("worklist_add", on_item(function(it)
    require("sprints.worklist").add(it)
  end))
  map("mine", function()
    state[bufnr].mine_only = not state[bufnr].mine_only
    load(bufnr)
  end)
  map("board", function()
    local s = state[bufnr]
    s.group = not s.group
    if s.shown then
      with_status_order(bufnr, function(order)
        draw(bufnr, order)
      end)
    end
  end)
  map("new", function()
    local target = state[bufnr].new_target
    if type(target) == "function" then
      target = target()
    end
    if not target then
      return vim.notify("sprints.nvim: this list isn't a sprint; use :SprintsNew", vim.log.levels.WARN)
    end
    require("sprints.ui.edit").new(target, function(new_ref)
      if vim.api.nvim_buf_is_valid(bufnr) then
        load(bufnr)
      end
      if new_ref.item then
        require("sprints.ui.item").open_ref(new_ref, "the new item")
      end
    end)
  end)
  map("close", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
  if keys.help then
    vim.keymap.set("n", keys.help, function()
      local lines = { "sprints.nvim list" }
      for _, h in ipairs(HELP) do
        if keys[h[1]] then
          table.insert(lines, ("  %-6s %s"):format(keys[h[1]], h[2]))
        end
      end
      vim.notify(table.concat(lines, "\n"))
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: help" })
  end
end

--- Open a list whose rows come from fetch(mine_only, cb); cb(items, err, title?).
---@param name string identifies the buffer (reopening reuses it)
---@param title string
---@param fetch fun(mine_only: boolean, cb: fun(items: table[]|nil, err: table|nil, title: string|nil))
---@param opts { mine_only: boolean|nil, group: boolean|nil, project: table|nil, new_target: table|nil }|nil
function M.open_with(name, title, fetch, opts)
  opts = opts or {}
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch("sprints://list/" .. name, "sprints-list")
  vim.b[bufnr].sprints_list_title = title
  state[bufnr] = {
    fetch = fetch,
    mine_only = opts.mine_only or false,
    group = opts.group or false,
    project = opts.project,
    new_target = opts.new_target,
    by_line = {},
  }
  if created then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        state[bufnr] = nil
      end,
    })
  end
  util.set_readonly(bufnr, true)
  setup_keymaps(bufnr)
  util.show(bufnr, { role = "list" })
  vim.wo.cursorline = true
  util.set_wrap(0, false) -- one row per item, even in a narrow split
  vim.wo.winbar = "<CR> open · n new · b board · m mine · yk key · g? more"
  load(bufnr)
  return bufnr
end

--- A list of `item`'s sub items.
function M.open_children(item)
  return M.open_with("children/" .. item.ref.item, item.key .. " — sub items", function(mine_only, cb)
    require("sprints.api.hierarchy").children(item, function(children, err)
      if not children or not mine_only then
        return cb(children, err)
      end
      require("sprints.api.workspace").me(item.ref.team, item.ref.project, function(me, merr)
        if not me then
          return cb(nil, merr)
        end
        cb(vim.tbl_filter(function(it)
          return vim.tbl_contains(it.owner_ids, me)
        end, children), nil)
      end)
    end)
  end, {
    -- no new_target: `n` here would make a top-level item, not a sub item
    project = { team = item.ref.team, project = item.ref.project },
  })
end

--- Re-fetch every open list (after creating or changing items elsewhere).
function M.refresh_all()
  for bufnr in pairs(state) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      load(bufnr)
    end
  end
end

M._state = state -- tests

return M
