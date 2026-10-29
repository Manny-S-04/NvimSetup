-- Item list buffer (a sprint, the backlog, your items). Ported from jira.nvim's list.
local render = require("sprints.ui.render")
local util = require("sprints.ui.util")

local M = {}

-- bufnr -> { fetch = fn(cb), mine_only = bool, by_line = table, shown = item[] }
-- (functions and item tables can't live in vim.b)
local state = {}

local function item_under_cursor(bufnr)
  local s = state[bufnr]
  return s and s.by_line[vim.api.nvim_win_get_cursor(0)[1]] or nil
end

local function load(bufnr)
  local s = state[bufnr]
  local title = vim.b[bufnr].sprints_list_title
  util.set_lines(bufnr, { "# " .. title, "", "Loading…" })

  s.fetch(s.mine_only, function(results, err, new_title)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if new_title then
      title = new_title
      vim.b[bufnr].sprints_list_title = new_title
    end
    if not results then
      util.set_lines(bufnr, { "# " .. title, "", "Error: " .. (err and err.message or "unknown error") })
      return util.notify_error("loading items failed", err)
    end
    local shown_title = s.mine_only and (title .. " (mine)") or title
    local lines, highlights, by_line = render.render_list(shown_title, results)
    s.by_line, s.shown = by_line, results
    util.set_lines(bufnr, lines)
    util.apply_highlights(bufnr, highlights)
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 and #results > 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { 3, 0 })
    end
  end)
end

local function setup_keymaps(bufnr)
  local keys = (require("sprints.config").options.keymaps or {}).list or {}
  local function map(name, fn, desc)
    if keys[name] then
      vim.keymap.set("n", keys[name], fn, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: " .. desc })
    end
  end
  map("open", function()
    local it = item_under_cursor(bufnr)
    if it then
      require("sprints.ui.item").open_ref(it.ref, it.key)
    end
  end, "open item")
  map("browser", function()
    local it = item_under_cursor(bufnr)
    if it then
      vim.ui.open(require("sprints.api.items").browse_url(it.ref, it.no))
    end
  end, "open item in browser")
  map("refresh", function()
    load(bufnr)
  end, "refresh list")
  map("mine", function()
    state[bufnr].mine_only = not state[bufnr].mine_only
    load(bufnr)
  end, "toggle: only my items")
  map("close", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, "close list")
end

--- Open a list whose rows come from fetch(mine_only, cb); cb(items, err, title?).
---@param name string identifies the buffer (reopening reuses it)
---@param title string
---@param fetch fun(mine_only: boolean, cb: fun(items: table[]|nil, err: table|nil, title: string|nil))
---@param opts { mine_only: boolean|nil }|nil
function M.open_with(name, title, fetch, opts)
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch("sprints://list/" .. name, "sprints-list")
  vim.b[bufnr].sprints_list_title = title
  state[bufnr] = { fetch = fetch, mine_only = (opts or {}).mine_only or false, by_line = {}, shown = {} }
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
  util.show(bufnr)
  vim.wo.cursorline = true
  load(bufnr)
  return bufnr
end

M._state = state -- tests

return M
