-- Scratch buffer for writing a comment, or editing one (opts.note_id). :w posts / saves it,
-- :q! abandons it.
local items = require("sprints.api.items")
local util = require("sprints.ui.util")

local M = {}

---@param ref table item ref
---@param key string|nil display key, for messages
---@param on_posted fun()|nil
---@param opts { note_id: string, lines: string[] }|nil edit that comment, starting from `lines`
function M.open(ref, key, on_posted, opts)
  key = key or ref.item
  opts = opts or {}
  local editing = opts.note_id ~= nil
  local name = editing and ("sprints://%s/%s/comment-%s"):format(ref.project, ref.item, opts.note_id)
    or ("sprints://%s/%s/new-comment"):format(ref.project, ref.item)
  local bufnr = util.find_buf_by_name(name)
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.bo[bufnr].buftype = "acwrite" -- :w triggers BufWriteCmd instead of writing a file
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].filetype = "markdown"
    if editing then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.lines or {})
      vim.bo[bufnr].modified = false
    end

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      callback = function()
        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        if not text:match("%S") then
          return vim.notify("sprints.nvim: comment is empty, nothing posted", vim.log.levels.WARN)
        end
        local verb = editing and "saved" or "posted"
        vim.notify(("sprints.nvim: %s comment on %s…"):format(editing and "saving" or "posting", key))
        local function done(ok, err)
          if not ok then
            return util.notify_error("comment failed", err) -- buffer (and text) kept
          end
          vim.notify(("sprints.nvim: comment %s on %s"):format(verb, key))
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.bo[bufnr].modified = false
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end
          if on_posted then
            on_posted()
          end
        end
        if editing then
          items.edit_comment(ref, opts.note_id, text, done)
        else
          items.add_comment(ref, text, done)
        end
      end,
    })
  end
  util.show(bufnr)
  vim.wo.winbar = editing and ("Editing comment on %s — :w to save, :q! to cancel"):format(key)
    or ("Comment on %s — :w to post, :q! to cancel"):format(key)
  if not editing then
    vim.cmd("startinsert")
  end
  return bufnr
end

return M
