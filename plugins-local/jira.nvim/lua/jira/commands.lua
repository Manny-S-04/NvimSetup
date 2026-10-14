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

local function open_board(id)
  local boards = require("jira.api.boards")
  require("jira.ui.list").open_with("board/" .. id, "Board " .. id, function(cb)
    boards.board_view(id, cb)
  end)
end

local function cmd_jira_board(cmd_opts)
  if not ensure_configured() then
    return
  end
  local arg = vim.trim(cmd_opts.args or "")
  local id = arg:match("^%d+$") or arg:match("/boards/(%d+)") -- accept a pasted board URL too
  if arg ~= "" and not id then
    vim.notify("jira.nvim: usage :JiraBoard [board id or board URL]", vim.log.levels.WARN)
    return
  end
  id = id or (config.options.board and tostring(config.options.board))
  if id then
    return open_board(id)
  end

  require("jira.api.boards").list(nil, function(list, err)
    if not list then
      return require("jira.ui.util").notify_error("could not list boards", err)
    end
    if #list == 0 then
      return vim.notify("jira.nvim: no boards visible to you", vim.log.levels.WARN)
    end
    vim.ui.select(list, {
      prompt = "Jira board",
      format_item = function(b)
        return ("%s  [%s%s, #%s]"):format(b.name, b.type or "?", b.project and (", " .. b.project) or "", b.id)
      end,
    }, function(choice)
      if choice then
        open_board(tostring(choice.id))
      end
    end)
  end)
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
    "  :JiraBoard [ID]      What a board shows (active sprint / open work); no ID = pick one",
    "  :JiraIssue [KEY]     Open an issue (defaults to the key under the cursor)",
    "  :JiraRefresh         Refresh the current issue buffer",
    "",
    "In a list / an issue: press the help key (default g?) in an issue buffer for its keys.",
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
  vim.api.nvim_create_user_command("JiraBoard", cmd_jira_board, {
    nargs = "?",
    desc = "List the issues a Jira board shows (active sprint for scrum boards)",
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
