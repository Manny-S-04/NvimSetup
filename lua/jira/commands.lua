local issues = require("jira.api.issues")
local issue_ui = require("jira.ui.issue")

local M = {}

local function notify_error(prefix, err)
  vim.notify(("jira.nvim: %s: %s"):format(prefix, err and err.message or "unknown error"), vim.log.levels.ERROR)
end

local function cmd_jira_issue(cmd_opts)
  local key = vim.trim(cmd_opts.args or "")
  if key == "" then
    vim.notify("jira.nvim: usage :JiraIssue <ISSUE-KEY>", vim.log.levels.WARN)
    return
  end

  local valid, key_err = issues.validate_key(key)
  if not valid then
    vim.notify("jira.nvim: " .. key_err, vim.log.levels.ERROR)
    return
  end

  local issue, err = issues.get(key)
  if not issue then
    notify_error("failed to fetch " .. key, err)
    return
  end

  issue_ui.open(issue)
end

local function cmd_jira_refresh()
  issue_ui.refresh(vim.api.nvim_get_current_buf())
end

local function cmd_jira_help()
  local lines = {
    "jira.nvim (early-stage)",
    "",
    "Commands:",
    "  :JiraIssue <KEY>   View a Jira issue, e.g. :JiraIssue PROJ-123",
    "  :JiraRefresh       Refresh the current Jira issue buffer",
    "",
    "Planned: comments, transitions, assignment, JQL search, boards/sprints.",
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("JiraIssue", cmd_jira_issue, {
    nargs = 1,
    desc = "View a Jira issue in a buffer",
  })

  vim.api.nvim_create_user_command("JiraRefresh", cmd_jira_refresh, {
    nargs = 0,
    desc = "Refresh the current Jira issue buffer",
  })

  vim.api.nvim_create_user_command("Jira", cmd_jira_help, {
    nargs = 0,
    desc = "Show jira.nvim help",
  })
end

return M
