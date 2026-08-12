local M = {}

local NS = vim.api.nvim_create_namespace('mini_complete')
local DOC_GAP = 1

local function set_default_highlights()
  vim.api.nvim_set_hl(0, 'MiniCompleteNormal', { bg = '#1e1e2e', fg = '#cdd6f4', default = true })
  vim.api.nvim_set_hl(0, 'MiniCompleteSelected', { bg = '#45475a', fg = '#f5e0dc', bold = true, default = true })
  vim.api.nvim_set_hl(0, 'MiniCompleteDocNormal', { bg = '#181825', fg = '#cdd6f4', default = true })
  vim.api.nvim_set_hl(0, 'MiniCompleteDocBorder', { fg = '#585b70', default = true })
  vim.api.nvim_set_hl(0, 'MiniCompleteSnippet', { fg = '#f38ba8', default = true })
  vim.api.nvim_set_hl(0, 'MiniCompleteSnippetSelected', { bg = '#45475a', fg = '#f38ba8', bold = true, default = true })
end

local state = {
  active = false,
  items = {},
  selected = 1,
  win = nil,
  buf = nil,
  start_col = nil,
  client_id = nil,
  doc_win = nil,
  doc_buf = nil,
  doc_lines = {},
  doc_scroll = 1,
  docs_shown = false,
  request_id = 0,
  doc_request_id = 0,
  leftcol = 0,
  doc_focused = false,
  return_win = nil,
  return_cursor = nil,
  suppress_next_change = false,
}

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', false)
end

local function close_doc_window()
  if state.doc_win and vim.api.nvim_win_is_valid(state.doc_win) then
    vim.api.nvim_win_close(state.doc_win, true)
  end
  state.doc_win = nil
  state.doc_lines = {}
end

local function close_window()
  if state.doc_focused then return end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.active = false
  state.items = {}
  state.docs_shown = false
  close_doc_window()
end

local function restore_after_doc_focus()
  if not state.doc_focused then return end
  state.doc_focused = false
  state.docs_shown = false
  state.doc_win = nil
  if state.return_win and vim.api.nvim_win_is_valid(state.return_win) then
    vim.api.nvim_set_current_win(state.return_win)
    if state.return_cursor then
      pcall(vim.api.nvim_win_set_cursor, state.return_win, state.return_cursor)
    end
    vim.cmd('startinsert')
  end
  state.return_win = nil
  state.return_cursor = nil
end

local function ensure_buf()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = 'nofile'
  end
  return state.buf
end

local function render()
  local buf = ensure_buf()
  local parts, highlights = {}, {}
  local col = 0
  local sel_start, sel_end = 0, 0
  for i, item in ipairs(state.items) do
    if i > 1 then
      table.insert(parts, '  ')
      col = col + 2
    end
    local start_col = col
    local text = item.label
    table.insert(parts, text)
    col = col + #text

    local is_selected = (i == state.selected)
    local is_snippet = item.__snippet ~= nil
    local group
    if is_selected and is_snippet then
      group = 'MiniCompleteSnippetSelected'
    elseif is_selected then
      group = 'MiniCompleteSelected'
    elseif is_snippet then
      group = 'MiniCompleteSnippet'
    end
    if group then
      table.insert(highlights, { start_col, col, group })
    end
    if is_selected then
      sel_start, sel_end = start_col, col
    end
  end

  local line = table.concat(parts)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, NS, hl[3], 0, hl[1], hl[2])
  end

  local width = vim.o.columns
  local row = vim.o.lines - vim.o.cmdheight - 2

  if sel_end > state.leftcol + width then
    state.leftcol = sel_end - width
  end
  if sel_start < state.leftcol then
    state.leftcol = sel_start
  end
  if state.leftcol < 0 then
    state.leftcol = 0
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, { relative = 'editor', row = row, col = 0, width = width, height = 1 })
  else
    state.win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = row,
      col = 0,
      width = width,
      height = 1,
      style = 'minimal',
      focusable = false,
      zindex = 250,
      border = 'none',
    })
    vim.wo[state.win].winhighlight = 'Normal:MiniCompleteNormal'
    vim.wo[state.win].wrap = false
  end

  vim.api.nvim_win_call(state.win, function()
    vim.fn.winrestview({ leftcol = state.leftcol })
  end)
end

local function documentation_to_lines(doc)
  if not doc then return {} end
  local text = type(doc) == 'string' and doc or (doc.value or '')
  text = text:gsub('\r\n', '\n')
  return vim.split(text, '\n', { plain = true })
end

local function render_docs(doc)
  local lines = documentation_to_lines(doc)
  if #lines == 0 then
    close_doc_window()
    return
  end
  state.doc_lines = lines
  state.doc_scroll = 1

  if not (state.doc_buf and vim.api.nvim_buf_is_valid(state.doc_buf)) then
    state.doc_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.doc_buf].buftype = 'nofile'
  end
  vim.bo[state.doc_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.doc_buf, 0, -1, false, lines)
  vim.bo[state.doc_buf].modifiable = false

  local candidate_row = vim.o.lines - vim.o.cmdheight - 2
  local available = candidate_row - DOC_GAP - 2
  local height = math.min(#lines, 12, available)
  if height < 1 then
    close_doc_window()
    return
  end
  local row = candidate_row - DOC_GAP - height - 1
  local width = vim.o.columns

  if state.doc_win and vim.api.nvim_win_is_valid(state.doc_win) then
    vim.api.nvim_win_set_config(state.doc_win, { relative = 'editor', row = row, col = 0, width = width, height = height })
  else
    state.doc_win = vim.api.nvim_open_win(state.doc_buf, false, {
      relative = 'editor',
      row = row,
      col = 0,
      width = width,
      height = height,
      style = 'minimal',
      focusable = false,
      zindex = 249,
      border = 'rounded',
    })
    vim.wo[state.doc_win].wrap = true
    vim.wo[state.doc_win].linebreak = true
    vim.wo[state.doc_win].winhighlight = 'Normal:MiniCompleteDocNormal,FloatBorder:MiniCompleteDocBorder'
  end
end

local function resolve_and_show_docs()
  local item = state.items[state.selected]
  if not item then
    close_doc_window()
    return
  end

  if item.__snippet then
    render_docs(item.__snippet:get_docstring() and table.concat(item.__snippet:get_docstring(), '\n') or item.label)
    return
  end

  state.doc_request_id = state.doc_request_id + 1
  local this_request = state.doc_request_id

  if item.documentation then
    render_docs(item.documentation)
    return
  end

  local client = state.client_id and vim.lsp.get_client_by_id(state.client_id)
  if not client then
    close_doc_window()
    return
  end

  client:request('completionItem/resolve', item, function(err, resolved)
    if this_request ~= state.doc_request_id then return end
    if not state.docs_shown then return end
    if err or not resolved then return end
    state.items[state.selected] = resolved
    render_docs(resolved.documentation)
  end, 0)
end

local function scroll_docs(delta)
  if not (state.doc_win and vim.api.nvim_win_is_valid(state.doc_win)) then return end
  local total = #state.doc_lines
  local win_height = vim.api.nvim_win_get_height(state.doc_win)
  local max_top = math.max(1, total - win_height + 1)
  state.doc_scroll = math.min(max_top, math.max(1, state.doc_scroll + delta * win_height))
  vim.api.nvim_win_call(state.doc_win, function()
    vim.fn.winrestview({ topline = state.doc_scroll })
  end)
end

local function get_prefix()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  local prefix = before:match('[%w_]*$') or ''
  return prefix, col - #prefix
end

local function get_client()
  local clients = vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/completion' })
  return clients[1]
end

local function get_snippet_matches(prefix)
  local ok, ls = pcall(require, 'luasnip')
  if not ok or prefix == '' then return {} end
  local ft = vim.bo.filetype
  local raw = ls.get_snippets(ft) or {}
  local matches = {}
  for _, snip in ipairs(raw) do
    local trigger = snip.trigger or ''
    if trigger:lower():find(prefix:lower(), 1, true) == 1 then
      table.insert(matches, {
        label = trigger,
        sortText = '0' .. trigger,
        __snippet = snip,
      })
    end
  end
  return matches
end

local function in_member_access(start_col)
  if start_col <= 0 then return false end
  local line = vim.api.nvim_get_current_line()
  local ch = line:sub(start_col, start_col)
  return ch == '.' or ch == ':'
end

local function request_completion()
  state.request_id = state.request_id + 1
  local this_request = state.request_id
  local client = get_client()

  local function finish(lsp_items)
    if this_request ~= state.request_id then return end

    local prefix, start_col = get_prefix()
    if prefix == '' then
      close_window()
      return
    end

    local filtered = {}
    for _, item in ipairs(lsp_items or {}) do
      local label = item.label or ''
      if label:lower():find(prefix:lower(), 1, true) == 1 then
        table.insert(filtered, item)
      end
    end
    for _, snip_item in ipairs(in_member_access(start_col) and {} or get_snippet_matches(prefix)) do
      table.insert(filtered, snip_item)
    end
    table.sort(filtered, function(a, b) return (a.sortText or a.label) < (b.sortText or b.label) end)

    if #filtered == 0 then
      close_window()
      return
    end

    state.items = filtered
    state.selected = 1
    state.active = true
    state.start_col = start_col
    state.client_id = client and client.id or nil
    state.docs_shown = false
    state.leftcol = 0
    close_doc_window()
    render()
  end

  if not client then
    finish({})
    return
  end

  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request('textDocument/completion', params, function(err, result)
    if err or not result then
      finish({})
      return
    end
    finish(result.items or result)
  end, 0)
end

function M.select_next()
  if not state.active then return end
  state.selected = state.selected % #state.items + 1
  render()
  if state.docs_shown then resolve_and_show_docs() end
end

function M.select_prev()
  if not state.active then return end
  state.selected = (state.selected - 2) % #state.items + 1
  render()
  if state.docs_shown then resolve_and_show_docs() end
end

function M.toggle_docs()
  if not state.active then return end
  if state.docs_shown then
    state.docs_shown = false
    close_doc_window()
  else
    state.docs_shown = true
    resolve_and_show_docs()
  end
end

function M.focus_docs()
  if not (state.active and state.docs_shown and state.doc_win and vim.api.nvim_win_is_valid(state.doc_win)) then
    return
  end

  state.return_win = vim.api.nvim_get_current_win()
  state.return_cursor = vim.api.nvim_win_get_cursor(0)
  state.doc_focused = true

  local doc_win = state.doc_win
  vim.api.nvim_win_set_config(doc_win, { focusable = true })
  vim.api.nvim_set_current_win(doc_win)
  vim.cmd('stopinsert')

  local doc_buf = vim.api.nvim_win_get_buf(doc_win)
  local exit_fn = function()
    if vim.api.nvim_win_is_valid(doc_win) then
      vim.api.nvim_win_close(doc_win, true)
    end
  end
  vim.keymap.set('n', 'q', exit_fn, { buffer = doc_buf, nowait = true })
  vim.keymap.set('n', '<Esc>', exit_fn, { buffer = doc_buf, nowait = true })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(doc_win),
    once = true,
    callback = restore_after_doc_focus,
  })
end

function M.accept()
  if not state.active then return end
  local item = state.items[state.selected]
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  if item.__snippet then
    state.suppress_next_change = true
    vim.api.nvim_buf_set_text(0, row, state.start_col, row, col, { '' })
    vim.api.nvim_win_set_cursor(0, { row + 1, state.start_col })
    close_window()
    local ok, ls = pcall(require, 'luasnip')
    if ok then
      ls.snip_expand(item.__snippet:copy())
    end
    return
  end

  local insert_text = item.insertText or item.label
  local lines = vim.split(insert_text, '\n', { plain = true })

  state.suppress_next_change = true
  vim.api.nvim_buf_set_text(0, row, state.start_col, row, col, lines)

  local last_line_len = #lines[#lines]
  local new_row, new_col
  if #lines == 1 then
    new_row = row
    new_col = state.start_col + last_line_len
  else
    new_row = row + #lines - 1
    new_col = last_line_len
  end
  vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })
  close_window()
end

function M.cancel()
  close_window()
end

function M.setup()
  set_default_highlights()

  local group = vim.api.nvim_create_augroup('MiniComplete', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.supports_method('textDocument/completion') then
        vim.notify('mini_complete: ' .. client.name .. ' attached (indexing may still take a moment)', vim.log.levels.INFO)
      end
    end,
  })

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    callback = function()
      if state.suppress_next_change then
        state.suppress_next_change = false
        return
      end
      local prefix = get_prefix()
      if #prefix >= 1 then
        request_completion()
      else
        state.request_id = state.request_id + 1
        close_window()
      end
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', { group = group, callback = close_window })

  vim.keymap.set('i', '<C-j>', function()
    if state.active then
      M.select_next()
    else
      feed('<C-j>')
    end
  end)

  vim.keymap.set('i', '<C-k>', function()
    if state.active then
      M.select_prev()
    else
      feed('<C-k>')
    end
  end)

  vim.keymap.set('i', '<CR>', function()
    if state.active then
      M.accept()
    else
      feed('<CR>')
    end
  end)

  vim.keymap.set('i', '<Esc>', function()
    if state.active then
      M.cancel()
    end
    feed('<Esc>')
  end)

  local function toggle_docs_handler(fallback_keys)
    return function()
      if state.active then
        M.toggle_docs()
      else
        feed(fallback_keys)
      end
    end
  end

  vim.keymap.set('i', '<F6>', toggle_docs_handler('<F6>'))

  vim.keymap.set('i', '<F7>', function()
    if state.active and state.docs_shown then
      M.focus_docs()
    else
      feed('<F7>')
    end
  end)

  vim.keymap.set('i', '<C-f>', function()
    if state.active and state.docs_shown and state.doc_win then
      scroll_docs(1)
    else
      feed('<C-f>')
    end
  end)

  vim.keymap.set('i', '<C-b>', function()
    if state.active and state.docs_shown and state.doc_win then
      scroll_docs(-1)
    else
      feed('<C-b>')
    end
  end)

  vim.keymap.set('i', '<C-l>', function()
    local ok, ls = pcall(require, 'luasnip')
    if ok and ls.jumpable(1) then
      ls.jump(1)
    else
      feed('<C-l>')
    end
  end)

  vim.keymap.set('i', '<C-h>', function()
    local ok, ls = pcall(require, 'luasnip')
    if ok and ls.jumpable(-1) then
      ls.jump(-1)
    else
      feed('<C-h>')
    end
  end)
end

return M
