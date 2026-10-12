local config = require("jira.config")

local M = {}

local function ensure_configured()
  return config.validate()
end

--- Issue key under the cursor (e.g. in a commit message or a TODO), or nil.
local function key_under_cursor()
  local word = vim.fn.expand("<cWORD>")
  return word:match("[A-Za-z][A-Za-z0-9_]*%-%d+")
end

local function cmd_jira_issue(cmd_opts)
  if not ensure_configured() then
    return
  end
  local key = vim.trim(cmd_opts.args or "")
  if key == "" then
    key = key_under_cursor() or ""
  end
  if key == "" then
    vim.notify("jira.nvim: usage :JiraIssue <ISSUE-KEY> (or put the cursor on a key)", vim.log.levels.WARN)
    return
  end
  require("jira.ui.issue").open_key(key:upper())
end

local function cmd_jira_mine()
  if not ensure_configured() then
    return
  end
  require("jira.ui.list").open("My issues", config.options.jql_mine)
end

local function cmd_jira_search(cmd_opts)
  if not ensure_configured() then
    return
  end
  local jql = vim.trim(cmd_opts.args or "")
  if jql == "" then
    vim.notify("jira.nvim: usage :JiraSearch <JQL>", vim.log.levels.WARN)
    return
  end
  require("jira.ui.list").open("Search: " .. jql, jql)
end

local function cmd_jira_refresh()
  require("jira.ui.issue").refresh(vim.api.nvim_get_current_buf())
end

local function cmd_jira_help()
  local lines = {
    "jira.nvim",
    "",
    "Commands:",
    "  :JiraMine            Your open issues",
    "  :JiraSearch <JQL>    Issues matching a JQL query",
    "  :JiraIssue [KEY]     Open an issue (defaults to the key under the cursor)",
    "  :JiraRefresh         Refresh the current issue buffer",
    "",
    "In a list:   <CR> open · gx browser · r refresh · q close",
    "In an issue: s status · c comment · a assign to me · gx browser · r refresh · q close",
    "",
    ("Connected to: %s (%s)"):format(
      config.options.url or "(not configured)",
      config.is_cloud() and "Cloud, API v3" or "Server/DC, API v2"
    ),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("JiraIssue", cmd_jira_issue, {
    nargs = "?",
    desc = "View a Jira issue in a buffer",
  })
  vim.api.nvim_create_user_command("JiraMine", cmd_jira_mine, {
    nargs = 0,
    desc = "List Jira issues assigned to you",
  })
  vim.api.nvim_create_user_command("JiraSearch", cmd_jira_search, {
    nargs = "+",
    desc = "List Jira issues matching JQL",
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
