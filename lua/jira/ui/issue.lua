-- Owns the "jira issue" buffer abstraction: creating, naming, rendering,
-- and refreshing issue buffers. This is the only module that should ever
-- touch nvim_create_buf/nvim_win_*/keymaps for issue views.
local issues = require("jira.api.issues")
local render = require("jira.ui.render")
local util = require("jira.ui.util")

local M = {}

local ns = vim.api.nvim_create_namespace("jira.nvim.issue")

local function buf_name(key)
  return "jira://" .. key
end

local function setup_highlight_groups()
  local set_hl = vim.api.nvim_set_hl
  set_hl(0, "jiraHeading", { link = "Title", default = true })
  set_hl(0, "jiraLabel", { link = "Identifier", default = true })
  set_hl(0, "jiraCommentAuthor", { link = "Special", default = true })
end

local function apply_highlights(bufnr, highlights)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, h.line, h.col_start, {
      end_col = h.col_end,
      hl_group = h.hl_group,
    })
  end
end

local function ensure_buffer(key)
  local name = buf_name(key)
  local bufnr = util.find_buf_by_name(name)
  if bufnr then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].filetype = "jira-issue"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  return bufnr
end

local function setup_keymaps(bufnr)
  local opts = { buffer = bufnr, nowait = true, silent = true }

  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end, vim.tbl_extend("force", opts, { desc = "Close Jira issue buffer" }))

  vim.keymap.set("n", "<leader>jr", function()
    M.refresh(bufnr)
  end, vim.tbl_extend("force", opts, { desc = "Refresh Jira issue" }))
end

local function render_into(bufnr, issue)
  local lines, highlights = render.render(issue)
  util.set_lines(bufnr, lines)
  apply_highlights(bufnr, highlights)

  vim.b[bufnr].jira_issue_key = issue.key
  vim.b[bufnr].jira_issue_id = issue.id
  vim.b[bufnr].jira_issue_url = issue.raw and issue.raw.self
  vim.b[bufnr].jira_issue_data = issue

  util.set_readonly(bufnr, true)
end

--- Open (or focus, if already open) a buffer showing the given issue.
---@param issue table as returned by jira.api.issues.get
---@return integer bufnr
function M.open(issue)
  setup_highlight_groups()

  local bufnr = ensure_buffer(issue.key)
  render_into(bufnr, issue)
  setup_keymaps(bufnr)

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    vim.cmd.split()
    vim.api.nvim_win_set_buf(0, bufnr)
  else
    vim.api.nvim_set_current_win(winid)
  end

  return bufnr
end

--- Re-fetch and re-render the issue shown in the given buffer.
---@param bufnr integer|nil defaults to the current buffer
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local key = vim.b[bufnr].jira_issue_key

  if not key then
    vim.notify("jira.nvim: this buffer is not a Jira issue buffer", vim.log.levels.ERROR)
    return
  end

  local issue, err = issues.get(key)
  if not issue then
    vim.notify(
      ("jira.nvim: failed to refresh %s: %s"):format(key, err and err.message or "unknown error"),
      vim.log.levels.ERROR
    )
    return
  end

  render_into(bufnr, issue)
  vim.notify("jira.nvim: refreshed " .. key, vim.log.levels.INFO)
end

return M
