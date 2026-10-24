-- Owns the "jira issue" buffer: creating, rendering, refreshing, and the actions
-- you can take on an issue from inside it.
local config = require("jira.config")
local issues = require("jira.api.issues")
local render = require("jira.ui.render")
local util = require("jira.ui.util")

local M = {}

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
  pcall(function()
    require("jira.worklist").update(issue) -- keep the worklist's status column current
  end)
end

--- Re-fetch and re-render the issue shown in the given buffer.
---@param bufnr integer|nil defaults to the current buffer
---@param on_done fun()|nil
function M.refresh(bufnr, on_done)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local key = vim.b[bufnr].jira_issue_key

  if not key then
    vim.notify("jira.nvim: this buffer is not a Jira issue buffer", vim.log.levels.WARN)
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

function M.unassign(bufnr)
  local key = vim.b[bufnr].jira_issue_key
  issues.unassign(key, function(ok, err)
    if not ok then
      return util.notify_error("could not unassign " .. key, err)
    end
    vim.notify("jira.nvim: unassigned " .. key)
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

function M.open_parent(bufnr)
  local key = vim.b[bufnr].jira_issue_key
  require("jira.api.hierarchy").parent(key, function(parent, err)
    if err then
      return util.notify_error("could not read " .. key, err)
    end
    if not parent then
      return vim.notify("jira.nvim: " .. key .. " has no parent", vim.log.levels.WARN)
    end
    M.open_key(parent.key)
  end)
end

function M.open_children(bufnr)
  require("jira.ui.list").open_children(vim.b[bufnr].jira_issue_key)
end

function M.work(bufnr)
  require("jira.worklist").work(vim.b[bufnr].jira_issue_key)
end

function M.worklist_add(bufnr)
  require("jira.worklist").add({ key = vim.b[bufnr].jira_issue_key })
end

-- action name -> { function, description }, in the order shown by the help key
local ACTIONS = {
  { "status", M.change_status, "change status (transition)" },
  { "comment", M.comment, "add a comment" },
  { "assign_me", M.assign_to_me, "assign to me" },
  { "unassign", M.unassign, "unassign" },
  { "browser", M.open_in_browser, "open in browser" },
  { "parent", M.open_parent, "open the parent" },
  { "children", M.open_children, "list child tickets" },
  { "work", M.work, "worklist = the parent's tickets (:JiraWork)" },
  { "worklist_add", M.worklist_add, "add to the worklist" },
  { "refresh", M.refresh, "refresh" },
  {
    "close",
    function(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end,
    "close",
  },
}

local function setup_keymaps(bufnr)
  local keys = (config.options.keymaps or {}).issue or {}
  local help = { "jira.nvim issue buffer" }

  for _, action in ipairs(ACTIONS) do
    local name, fn, desc = action[1], action[2], action[3]
    local lhs = keys[name]
    if lhs then
      vim.keymap.set("n", lhs, function()
        fn(bufnr)
      end, { buffer = bufnr, nowait = true, silent = true, desc = "Jira: " .. desc })
      table.insert(help, ("  %-6s %s"):format(lhs, desc))
    end
  end

  if keys.help then
    vim.keymap.set("n", keys.help, function()
      vim.notify(table.concat(help, "\n"))
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Jira: help" })
  end
end

--- Open (or focus, if already open) a buffer showing the given issue.
---@param issue table as returned by jira.api.issues.get
---@return integer bufnr
function M.open(issue, opts)
  util.setup_highlight_groups()

  local bufnr = util.named_scratch(buf_name(issue.key), "jira-issue")
  render_into(bufnr, issue)
  setup_keymaps(bufnr)
  util.show(bufnr, opts)

  return bufnr
end

--- Fetch an issue asynchronously and open it.
---@param opts table|nil { reuse_window = boolean } (see jira.ui.util.show)
function M.open_key(key, opts)
  local valid, key_err = issues.validate_key(key)
  if not valid then
    vim.notify("jira.nvim: " .. key_err, vim.log.levels.WARN)
    return
  end
  vim.notify("jira.nvim: loading " .. key .. "…")
  issues.get(key, function(issue, err)
    if not issue then
      return util.notify_error("failed to fetch " .. key, err)
    end
    M.open(issue, opts)
  end)
end

return M
