-- Small, generic buffer helpers shared across jira.nvim's UI modules.
local M = {}

function M.find_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
  return nil
end

--- Replace buffer contents, temporarily making it modifiable.
function M.set_lines(bufnr, lines)
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
end

function M.set_readonly(bufnr, readonly)
  vim.bo[bufnr].modifiable = not readonly
  vim.bo[bufnr].readonly = readonly
end

return M
