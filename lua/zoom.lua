-- Zoom: show the current window full-screen, and put everything back with the same key.
-- Done as a temporary tab holding the same buffer, rather than :only or resizing, so the
-- original layout (dap-ui panels, splits, their sizes) is never touched and can't get mangled.
local M = {}

---@return boolean
function M.is_zoomed()
    return vim.t.zoom_from ~= nil
end

function M.zoom()
    if M.is_zoomed() then return end
    local from = vim.api.nvim_get_current_tabpage()
    vim.cmd("tab split") -- same buffer, same cursor, same view
    vim.t.zoom_from = from
end

function M.unzoom()
    local from = vim.t.zoom_from
    if not from then return end
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.cmd("tabclose")
    if vim.api.nvim_tabpage_is_valid(from) then
        vim.api.nvim_set_current_tabpage(from)
    end
    -- carry the cursor back if the window we land in shows the same buffer
    if vim.api.nvim_get_current_buf() == buf then
        pcall(vim.api.nvim_win_set_cursor, 0, cursor)
    end
end

function M.toggle()
    if M.is_zoomed() then M.unzoom() else M.zoom() end
end

return M
