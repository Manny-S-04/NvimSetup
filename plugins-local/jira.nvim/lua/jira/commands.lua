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
  local input = vim.trim(cmd_opts.args or "")
  if input == "" then
    return require("jira.ui.find").open()
  end
  require("jira.ui.list").open("Search: " .. input, require("jira.jql").from_freeform(input))
end

local function cmd_jira_find(cmd_opts)
  if not ensure_configured() then
    return
  end
  local name = vim.trim(cmd_opts.args or "")
  if name == "" then
    return require("jira.ui.find").open()
  end
  if not require("jira.ui.find").run_preset(name) then
    vim.notify(("jira.nvim: no preset %q (see :JiraFind → Presets…)"):format(name), vim.log.levels.WARN)
  end
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

--- KEY from the args, else the issue buffer you're in, else the key under the cursor.
local function key_arg(cmd_opts)
  local key = vim.trim(cmd_opts.args or "")
  if key == "" then
    key = vim.b.jira_issue_key or key_under_cursor() or ""
  end
  return key ~= "" and key:upper() or nil
end

local function with_key(usage, fn)
  return function(cmd_opts)
    if not ensure_configured() then
      return
    end
    local key = key_arg(cmd_opts)
    if not key then
      return vim.notify("jira.nvim: usage " .. usage, vim.log.levels.WARN)
    end
    local ok, err = require("jira.api.issues").validate_key(key)
    if not ok then
      return vim.notify("jira.nvim: " .. err, vim.log.levels.WARN)
    end
    fn(key)
  end
end

local cmd_jira_children = with_key(":JiraChildren [KEY]", function(key)
  require("jira.ui.list").open_children(key)
end)

local cmd_jira_parent = with_key(":JiraParent [KEY]", function(key)
  require("jira.api.hierarchy").parent(key, function(parent, err)
    if err then
      return require("jira.ui.util").notify_error("could not read " .. key, err)
    end
    if not parent then
      return vim.notify("jira.nvim: " .. key .. " has no parent", vim.log.levels.WARN)
    end
    require("jira.ui.issue").open_key(parent.key)
  end)
end)

local cmd_jira_work = with_key(":JiraWork [KEY]", function(key)
  require("jira.worklist").work(key)
end)

local function cmd_jira_worklist(cmd_opts)
  local sub = vim.trim(cmd_opts.args or "")
  local wl = require("jira.worklist")
  if sub == "" then
    wl.open()
  elseif sub == "refresh" then
    if ensure_configured() then
      wl.refresh()
    end
  elseif sub == "add" then
    wl.add()
  elseif sub == "next" then
    wl.next()
  elseif sub == "prev" then
    wl.prev()
  else
    vim.notify("jira.nvim: usage :JiraWorklist [refresh|add|next|prev]", vim.log.levels.WARN)
  end
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
    "  :JiraFind [PRESET]   Build a query from menus (no JQL needed), or run a saved preset",
    "  :JiraSearch [JQL]    Issues matching JQL; a bare KEY or plain words also work; no arg = :JiraFind",
    "  :JiraBoard [ID]      What a board shows (active sprint / open work); no ID = pick one",
    "  :JiraIssue [KEY]     Open an issue (defaults to the key under the cursor)",
    "  :JiraRefresh         Refresh the current issue buffer",
    "  :JiraParent [KEY]    Open KEY's parent",
    "  :JiraChildren [KEY]  List KEY's child tickets",
    "  :JiraWork [KEY]      Worklist = KEY's parent's child tickets (needs harpoon)",
    "  :JiraWorklist [sub]  Open the worklist; refresh | add | next | prev",
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
  vim.api.nvim_create_user_command("JiraFind", cmd_jira_find, {
    nargs = "?",
    complete = function()
      return require("jira.presets").names()
    end,
    desc = "Build a Jira query from menus, or run a saved preset",
  })
  vim.api.nvim_create_user_command("JiraSearch", cmd_jira_search, {
    nargs = "*",
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
  vim.api.nvim_create_user_command("JiraParent", cmd_jira_parent, {
    nargs = "?",
    desc = "Open the parent of a Jira issue",
  })
  vim.api.nvim_create_user_command("JiraChildren", cmd_jira_children, {
    nargs = "?",
    desc = "List the child tickets of a Jira issue",
  })
  vim.api.nvim_create_user_command("JiraWork", cmd_jira_work, {
    nargs = "?",
    desc = "Make the parent's child tickets your worklist",
  })
  vim.api.nvim_create_user_command("JiraWorklist", cmd_jira_worklist, {
    nargs = "?",
    complete = function()
      return { "refresh", "add", "next", "prev" }
    end,
    desc = "Open / refresh / step through the Jira worklist",
  })
  vim.api.nvim_create_user_command("Jira", cmd_jira_help, {
    nargs = 0,
    desc = "Show jira.nvim help",
  })
end

return M
