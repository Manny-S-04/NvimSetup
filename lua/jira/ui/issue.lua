-- Owns the "jira issue" buffer: creating, rendering, refreshing, and the actions
-- you can take on an issue from inside it.
local issues = require("jira.api.issues")
local render = require("jira.ui.render")
local util = require("jira.ui.util")

local M = {}

local HELP = {
  "jira.nvim issue buffer",
  "  s     change status (transition)",
  "  c     add a comment",
  "  a     assign to me",
  "  gx    open in browser",
  "  r     refresh",
  "  q     close",
}

local function buf_name(key)
  return "jira://" .. key
end

local function render_into(bufnr, issue)
  local lines, highlights = render.render(issue)
  util.set_lines(bufnr, lines)
  util.apply_highlights(bufnr, highlights)

  vim.b[bufnr].jira_issue_key = issue.key
  vim.b[bufnr].jira_issue_id = issue.id
  vim.b[bufnr].jira_issue_url = issues.browse_url(issue.key)

  util.set_readonly(bufnr, true)
end

--- Re-fetch and re-render the issue shown in the given buffer.
---@param bufnr integer|nil defaults to the current buffer
---@param on_done fun()|nil
function M.refresh(bufnr, on_done)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local key = vim.b[bufnr].jira_issue_key

  if not key then
    vim.notify("jira.nvim: this buffer is not a Jira issue buffer", vim.log.levels.ERROR)
    return
  end

  issues.get(key, function(issue, err)
    if not issue then
      util.notify_error("failed to refresh " .. key, err)
      return
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      render_into(bufnr, issue)
    end
    if on_done then
      on_done()
    end
  end)
end

function M.change_status(bufnr)
  local key = vim.b[bufnr].jira_issue_key
  issues.transitions(key, function(transitions, err)
    if not transitions then
      return util.notify_error("could not load transitions for " .. key, err)
    end
    if #transitions == 0 then
      return vim.notify("jira.nvim: no transitions available for " .. key, vim.log.levels.WARN)
    end
    vim.ui.select(transitions, {
      prompt = key .. " → ",
      format_item = function(t)
        if t.to and t.to ~= t.name then
          return ("%s  (→ %s)"):format(t.name, t.to)
        end
        return t.name
      end,
    }, function(choice)
      if not choice then
        return
      end
      issues.transition(key, choice.id, function(ok, terr)
        if not ok then
          return util.notify_error("transition failed", terr)
        end
        vim.notify(("jira.nvim: %s → %s"):format(key, choice.to or choice.name))
        M.refresh(bufnr)
      end)
    end)
  end)
end

function M.assign_to_me(bufnr)
  local key = vim.b[bufnr].jira_issue_key
  issues.assign_to_me(key, function(ok, err)
    if not ok then
      return util.notify_error("could not assign " .. key, err)
    end
    vim.notify("jira.nvim: assigned " .. key .. " to you")
    M.refresh(bufnr)
  end)
end

function M.comment(bufnr)
  local key = vim.b[bufnr].jira_issue_key
  require("jira.ui.comment").open(key, function()
    M.refresh(bufnr)
  end)
end

function M.open_in_browser(bufnr)
  local url = vim.b[bufnr].jira_issue_url
  if url then
    vim.ui.open(url)
  end
end

local function setup_keymaps(bufnr)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, function()
      fn(bufnr)
    end, { buffer = bufnr, nowait = true, silent = true, desc = desc })
  end

  map("q", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, "Close Jira issue buffer")
  map("r", M.refresh, "Refresh Jira issue")
  map("<leader>jr", M.refresh, "Refresh Jira issue")
  map("s", M.change_status, "Change Jira issue status")
  map("c", M.comment, "Comment on Jira issue")
  map("a", M.assign_to_me, "Assign Jira issue to me")
  map("gx", M.open_in_browser, "Open Jira issue in browser")
  map("g?", function()
    vim.notify(table.concat(HELP, "\n"))
  end, "Jira issue help")
end

--- Open (or focus, if already open) a buffer showing the given issue.
---@param issue table as returned by jira.api.issues.get
---@return integer bufnr
function M.open(issue)
  util.setup_highlight_groups()

  local bufnr = util.named_scratch(buf_name(issue.key), "jira-issue")
  render_into(bufnr, issue)
  setup_keymaps(bufnr)
  util.show(bufnr)

  return bufnr
end

--- Fetch an issue asynchronously and open it.
function M.open_key(key)
  local valid, key_err = issues.validate_key(key)
  if not valid then
    vim.notify("jira.nvim: " .. key_err, vim.log.levels.ERROR)
    return
  end
  vim.notify("jira.nvim: loading " .. key .. "…")
  issues.get(key, function(issue, err)
    if not issue then
      return util.notify_error("failed to fetch " .. key, err)
    end
    M.open(issue)
  end)
end

return M
