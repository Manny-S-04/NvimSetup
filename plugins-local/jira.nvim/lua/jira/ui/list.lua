-- Issue list buffer (results of a JQL search).
local issues = require("jira.api.issues")
local render = require("jira.ui.render")
local util = require("jira.ui.util")

local M = {}

-- bufnr -> function(cb) that fetches the list: cb(issues, err, title?). Functions can't live in vim.b.
local fetchers = {}

local function key_under_cursor(bufnr)
  local keys = vim.b[bufnr].jira_list_keys or {}
  return keys[tostring(vim.api.nvim_win_get_cursor(0)[1])]
end

local function load(bufnr)
  local title = vim.b[bufnr].jira_list_title
  util.set_lines(bufnr, { "# " .. title, "", "Loading…" })

  local fetch = fetchers[bufnr]
  if not fetch then
    local jql = vim.b[bufnr].jira_list_jql
    fetch = function(cb)
      issues.search(jql, cb)
    end
  end

  fetch(function(results, err, new_title)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if new_title then
      title = new_title
      vim.b[bufnr].jira_list_title = new_title
    end
    if not results then
      util.set_lines(bufnr, { "# " .. title, "", "Error: " .. (err and err.message or "unknown error") })
      return util.notify_error("search failed", err)
    end

    local lines, highlights, keys = render.render_list(title, results)
    util.set_lines(bufnr, lines)
    util.apply_highlights(bufnr, highlights)
    -- string keys: vim.b can't store sparse integer-keyed tables reliably
    local by_line = {}
    for line, key in pairs(keys) do
      by_line[tostring(line)] = key
    end
    vim.b[bufnr].jira_list_keys = by_line

    -- put the cursor on the first issue
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 and #results > 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { 3, 0 })
    end
  end)
end

local function setup_keymaps(bufnr)
  local keys = (require("jira.config").options.keymaps or {}).list or {}
  local function map(name, fn, desc)
    if keys[name] then
      vim.keymap.set("n", keys[name], fn, { buffer = bufnr, nowait = true, silent = true, desc = "Jira: " .. desc })
    end
  end
  map("open", function()
    local key = key_under_cursor(bufnr)
    if key then
      require("jira.ui.issue").open_key(key)
    end
  end, "open issue")
  map("browser", function()
    local key = key_under_cursor(bufnr)
    if key then
      vim.ui.open(issues.browse_url(key))
    end
  end, "open issue in browser")
  map("refresh", function()
    load(bufnr)
  end, "refresh list")
  map("close", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, "close list")
end

--- Open a list buffer whose contents come from `fetch(cb)`; cb(issues, err, title?).
--- `name` identifies the buffer (reopening the same name reuses it); the title may be
--- replaced by the fetcher once it knows more (e.g. the sprint name).
---@param name string
---@param title string
---@param fetch fun(cb: fun(issues: table[]|nil, err: table|nil, title: string|nil))
function M.open_with(name, title, fetch)
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch("jira://list/" .. name, "jira-list")
  vim.b[bufnr].jira_list_title = title
  fetchers[bufnr] = fetch
  if created then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        fetchers[bufnr] = nil
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

--- Open a list buffer for the given JQL.
---@param title string
---@param jql string
function M.open(title, jql)
  return M.open_with(title, title, function(cb)
    issues.search(jql, cb)
  end)
end

return M
