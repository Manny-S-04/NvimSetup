-- Small, generic buffer helpers shared across sprints.nvim's UI modules.
local M = {}

function M.find_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
  return nil
end

--- Replace buffer contents, temporarily making it modifiable (and not readonly,
--- otherwise every refresh triggers "W10: Warning: Changing a readonly file").
function M.set_lines(bufnr, lines)
  local was_modifiable, was_readonly = vim.bo[bufnr].modifiable, vim.bo[bufnr].readonly
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
  vim.bo[bufnr].readonly = was_readonly
  vim.bo[bufnr].modified = false
end

function M.set_readonly(bufnr, readonly)
  vim.bo[bufnr].modifiable = not readonly
  vim.bo[bufnr].readonly = readonly
end

function M.setup_highlight_groups()
  local set_hl = vim.api.nvim_set_hl
  set_hl(0, "sprintsHeading", { link = "Title", default = true })
  set_hl(0, "sprintsLabel", { link = "Identifier", default = true })
  set_hl(0, "sprintsKey", { link = "Special", default = true })
  set_hl(0, "sprintsCommentAuthor", { link = "Special", default = true })
  set_hl(0, "sprintsStatusTodo", { link = "Comment", default = true })
  set_hl(0, "sprintsStatusProgress", { link = "DiagnosticWarn", default = true })
  set_hl(0, "sprintsStatusDone", { link = "DiagnosticOk", default = true })
end

local ns = vim.api.nvim_create_namespace("sprints.nvim")

function M.apply_highlights(bufnr, highlights)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, h.line, h.col_start, {
      end_col = h.col_end,
      hl_group = h.hl_group,
    })
  end
end

--- Get (or create) a scratch buffer with a stable sprints:// name.
function M.named_scratch(name, filetype)
  local bufnr = M.find_buf_by_name(name)
  if bufnr then
    return bufnr, false
  end
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].filetype = filetype
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "hide"
  return bufnr, true
end

--- Show a buffer: focus its window if visible, otherwise open it in a split.
--- opts.reuse_window: if the current window already shows a sprints buffer, show it there instead
--- of splitting again (worklist next/prev would otherwise stack up splits).
function M.show(bufnr, opts)
  opts = opts or {}
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    local open_cmd = require("sprints.config").options.open_cmd or "split"
    if opts.reuse_window and vim.bo.filetype:match("^sprints%-") then
      open_cmd = "edit"
    end
    if open_cmd ~= "edit" then
      vim.cmd(open_cmd)
    end
    vim.api.nvim_win_set_buf(0, bufnr)
  else
    vim.api.nvim_set_current_win(winid)
  end
end

function M.notify_error(prefix, err)
  vim.notify(("sprints.nvim: %s: %s"):format(prefix, err and err.message or "unknown error"), vim.log.levels.ERROR)
end

return M
