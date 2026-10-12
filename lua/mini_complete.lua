local M = {}

local NS = vim.api.nvim_create_namespace('mini_complete')
local DOC_GAP = 1
local DEBOUNCE_MS = 30
local RESOLVE_TIMEOUT_MS = 300

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
  row = nil, -- 0-based row the popup was opened for
  doc_win = nil,
  doc_buf = nil,
  docs_shown = false,
  request_id = 0,
  doc_request_id = 0,
  cancel_request = nil, -- cancels the in-flight textDocument/completion requests
  leftcol = 0,
  doc_focused = false,
  doc_exiting = false,
  return_win = nil,
  return_cursor = nil,
  just_accepted = false, -- swallow buffer changes caused by accept() until the user types again
  notified_clients = {},
}
M._state = state -- exposed for tests / debugging

local debounce_timer = assert(vim.uv.new_timer())

-- Re-send a key we intercepted but don't want to handle. The 'i' flag puts it at the
-- *front* of the typeahead; without it the key is appended to the end, so in macros,
-- `.` repeat and pastes it runs after keys that were typed later ("a<CR>b" -> "ab\n").
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'in', false)
end

-- Copy of an LSP item without our private "__" fields, safe to send back to the server.
local function lsp_item(item)
  local out = {}
  for k, v in pairs(item) do
    if type(k) ~= 'string' or k:sub(1, 2) ~= '__' then out[k] = v end
  end
  return out
end

-- LSP 3.17 CompletionList.itemDefaults: fields the server sends once for the whole list.
-- Items only carry what differs, so they must be merged back before use.
local function apply_item_defaults(item, defaults)
  if not defaults then return item end
  if defaults.editRange and not item.textEdit then
    local r = defaults.editRange
    local new_text = item.textEditText or item.label
    if r.insert then
      item.textEdit = { newText = new_text, insert = r.insert, replace = r.replace }
    else
      item.textEdit = { newText = new_text, range = r }
    end
  end
  if item.insertTextFormat == nil then item.insertTextFormat = defaults.insertTextFormat end
  if item.insertTextMode == nil then item.insertTextMode = defaults.insertTextMode end
  if item.data == nil then item.data = defaults.data end
  return item
end

local function close_doc_window()
  if state.doc_win and vim.api.nvim_win_is_valid(state.doc_win) then
    vim.api.nvim_win_close(state.doc_win, true)
  end
  state.doc_win = nil
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
  state.doc_request_id = state.doc_request_id + 1
  close_doc_window()
end

local function cancel_pending()
  debounce_timer:stop()
  state.request_id = state.request_id + 1
  if state.cancel_request then
    pcall(state.cancel_request)
    state.cancel_request = nil
  end
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
  local byte_col, disp_col = 0, 0
  local sel_start, sel_end = 0, 0 -- display columns, for horizontal scrolling
  for i, item in ipairs(state.items) do
    if i > 1 then
      table.insert(parts, '  ')
      byte_col, disp_col = byte_col + 2, disp_col + 2
    end
    local text = (item.label or ''):gsub('\n', ' ')
    local b_start, d_start = byte_col, disp_col
    table.insert(parts, text)
    byte_col = byte_col + #text
    disp_col = disp_col + vim.fn.strdisplaywidth(text)

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
      table.insert(highlights, { b_start, byte_col, group })
    end
    if is_selected then
      sel_start, sel_end = d_start, disp_col
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { table.concat(parts) })
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, NS, 0, hl[1], { end_col = hl[2], hl_group = hl[3] })
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

local function item_doc_lines(item)
  local lines = {}
  if item.detail and item.detail ~= '' then
    vim.list_extend(lines, vim.split(item.detail:gsub('\r\n', '\n'), '\n', { plain = true }))
  end
  local doc = item.documentation
  if doc then
    local text = type(doc) == 'string' and doc or (doc.value or '')
    text = text:gsub('\r\n', '\n')
    if text ~= '' then
      if #lines > 0 then table.insert(lines, '') end
      vim.list_extend(lines, vim.split(text, '\n', { plain = true }))
    end
  end
  return lines
end

local function render_docs(lines)
  if #lines == 0 then
    close_doc_window()
    return
  end

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
    -- scroll by screen lines, so <C-f>/<C-b> stay correct when long lines wrap
    vim.wo[state.doc_win].smoothscroll = true
    vim.wo[state.doc_win].winhighlight = 'Normal:MiniCompleteDocNormal,FloatBorder:MiniCompleteDocBorder'
  end
  vim.api.nvim_win_call(state.doc_win, function()
    vim.fn.winrestview({ topline = 1, skipcol = 0 })
  end)
end

local function resolve_and_show_docs()
  local item = state.items[state.selected]
  if not item then
    close_doc_window()
    return
  end

  if item.__snippet then
    local docstring = item.__snippet:get_docstring()
    render_docs(docstring and vim.split(table.concat(docstring, '\n'), '\n', { plain = true }) or { item.label })
    return
  end

  state.doc_request_id = state.doc_request_id + 1
  local this_request = state.doc_request_id

  local client = item.__client_id and vim.lsp.get_client_by_id(item.__client_id)
  local can_resolve = client and client:supports_method('completionItem/resolve')

  if item.__resolved or item.documentation or not can_resolve then
    render_docs(item_doc_lines(item))
    return
  end

  client:request('completionItem/resolve', lsp_item(item), function(err, resolved)
    if this_request ~= state.doc_request_id then return end
    if not state.docs_shown then return end
    if err or not resolved then
      render_docs(item_doc_lines(item))
      return
    end
    local merged = vim.tbl_extend('force', item, resolved)
    merged.__resolved = true
    state.items[state.selected] = merged
    render_docs(item_doc_lines(merged))
  end, 0)
end

local function scroll_docs(delta)
  if not (state.doc_win and vim.api.nvim_win_is_valid(state.doc_win)) then return end
  local win_height = vim.api.nvim_win_get_height(state.doc_win)
  local key = delta > 0 and '\5' or '\25' -- <C-e> / <C-y>
  vim.api.nvim_win_call(state.doc_win, function()
    vim.cmd('normal! ' .. win_height .. key)
  end)
end

local function get_prefix()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  -- \k follows 'iskeyword', so this handles non-ASCII identifiers and per-filetype word chars
  local prefix = vim.fn.matchstr(before, [[\k*$]])
  return prefix, col - #prefix
end

local function completion_clients()
  return vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/completion' })
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
  cancel_pending()
  local this_request = state.request_id
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = completion_clients()

  local function finish(lsp_items)
    if this_request ~= state.request_id then return end
    if vim.api.nvim_get_current_buf() ~= bufnr or vim.fn.mode() ~= 'i' then return end
    state.cancel_request = nil

    local prefix, start_col = get_prefix()
    if prefix == '' then
      close_window()
      return
    end

    local lower_prefix = prefix:lower()
    local filtered = {}
    for _, item in ipairs(lsp_items) do
      local key = item.filterText or item.label or ''
      if key:lower():find(lower_prefix, 1, true) == 1 then
        table.insert(filtered, item)
      end
    end
    for _, snip_item in ipairs(in_member_access(start_col) and {} or get_snippet_matches(prefix)) do
      table.insert(filtered, snip_item)
    end
    table.sort(filtered, function(a, b)
      return (a.sortText or a.label or '') < (b.sortText or b.label or '')
    end)

    if #filtered == 0 then
      close_window()
      return
    end

    state.items = filtered
    state.selected = 1
    state.active = true
    state.start_col = start_col
    state.row = vim.api.nvim_win_get_cursor(0)[1] - 1
    state.docs_shown = false
    state.doc_request_id = state.doc_request_id + 1
    state.leftcol = 0
    close_doc_window()
    render()
  end

  if #clients == 0 then
    finish({})
    return
  end

  local params = function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end
  state.cancel_request = vim.lsp.buf_request_all(bufnr, 'textDocument/completion', params, function(results)
    local items = {}
    for client_id, res in pairs(results) do
      local result = res.result
      if not res.err and result then
        local list = result.items or result
        local defaults = result.itemDefaults
        for _, item in ipairs(list) do
          item.__client_id = client_id
          table.insert(items, apply_item_defaults(item, defaults))
        end
      end
    end
    finish(items)
  end)
end

local function schedule_completion()
  debounce_timer:stop()
  debounce_timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(request_completion))
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
    state.doc_request_id = state.doc_request_id + 1
    close_doc_window()
  else
    state.docs_shown = true
    resolve_and_show_docs()
  end
end

-- Leave the focused docs window and go back to where we were, in insert mode.
local function exit_doc_focus()
  if not state.doc_focused then return end
  state.doc_exiting = true
  state.doc_focused = false
  state.docs_shown = false
  local doc_win = state.doc_win
  state.doc_win = nil
  if state.return_win and vim.api.nvim_win_is_valid(state.return_win) then
    vim.api.nvim_set_current_win(state.return_win)
  end
  if doc_win and vim.api.nvim_win_is_valid(doc_win) then
    vim.api.nvim_win_close(doc_win, true)
  end
  if state.return_win and vim.api.nvim_win_is_valid(state.return_win) and state.return_cursor then
    local row, col = state.return_cursor[1], state.return_cursor[2]
    pcall(vim.api.nvim_win_set_cursor, state.return_win, state.return_cursor)
    local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.return_win), row - 1, row, false)[1] or ''
    -- Normal mode can't sit past the last char, so at end of line we must append, not insert.
    vim.cmd(col >= #line and 'startinsert!' or 'startinsert')
  end
  state.return_win = nil
  state.return_cursor = nil
  state.doc_exiting = false
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
  vim.keymap.set('n', 'q', exit_doc_focus, { buffer = doc_buf, nowait = true })
  vim.keymap.set('n', '<Esc>', exit_doc_focus, { buffer = doc_buf, nowait = true })

  -- Leaving the docs window any other way (<C-w>p, :q, mouse) must not leave us stuck
  -- with doc_focused = true, which would stop close_window() from ever running again.
  local group = vim.api.nvim_create_augroup('MiniCompleteDocFocus', { clear = true })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = doc_buf,
    once = true,
    callback = function()
      if state.doc_exiting then return end
      vim.schedule(function()
        state.doc_focused = false
        state.return_win = nil
        state.return_cursor = nil
        close_window()
      end)
    end,
  })
end

-- Convert an LSP position's character offset on `row` to a byte column.
local function to_byte_col(row, character, encoding)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1] or ''
  local ok, col = pcall(vim.str_byteindex, line, encoding or 'utf-16', character, false)
  return ok and col or character
end

local function expand_lsp_snippet(body)
  local ok, ls = pcall(require, 'luasnip')
  if ok then
    ls.lsp_expand(body) -- keeps your <C-l>/<C-h> LuaSnip jump mappings working
  else
    vim.snippet.expand(body)
  end
end

function M.accept()
  if not state.active then return end
  local item = state.items[state.selected]
  if not item then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]

  if item.__snippet then
    state.just_accepted = true
    vim.api.nvim_buf_set_text(0, row, state.start_col, row, col, { '' })
    vim.api.nvim_win_set_cursor(0, { row + 1, state.start_col })
    close_window()
    local ok, ls = pcall(require, 'luasnip')
    if ok then
      ls.snip_expand(item.__snippet:copy())
    end
    return
  end

  local client = item.__client_id and vim.lsp.get_client_by_id(item.__client_id)
  local encoding = client and client.offset_encoding or 'utf-16'

  -- Auto-import edits (additionalTextEdits) are often only sent on resolve.
  if client and not item.__resolved and not item.additionalTextEdits
      and client:supports_method('completionItem/resolve') then
    local res = client:request_sync('completionItem/resolve', lsp_item(item), RESOLVE_TIMEOUT_MS, 0)
    if res and not res.err and res.result then
      -- merge, don't replace: the resolved copy lacks fields we filled in from itemDefaults
      item = vim.tbl_extend('force', item, res.result)
      item.__resolved = true
    end
  end

  -- What to insert, and where it starts. Per the LSP spec textEdit wins over insertText,
  -- which wins over label. The edit runs to the *current* cursor, since the user may have
  -- typed more characters after the request was sent.
  local text, start_col
  local edit = item.textEdit
  local range = edit and (edit.range or edit.insert)
  if range and range.start.line == row then
    text = edit.newText
    start_col = to_byte_col(row, range.start.character, encoding)
  else
    text = (edit and edit.newText) or item.insertText or item.label or ''
    start_col = state.start_col
  end
  start_col = math.min(start_col, col)
  text = text:gsub('\r\n', '\n')

  state.just_accepted = true
  close_window()

  -- Remove what the user typed, then remember that spot with an extmark so it survives
  -- additionalTextEdits inserting lines above it (e.g. a new `using` line).
  vim.api.nvim_buf_set_text(0, row, start_col, row, col, { '' })
  local mark = vim.api.nvim_buf_set_extmark(0, NS, row, start_col, {})

  if item.additionalTextEdits and #item.additionalTextEdits > 0 then
    vim.lsp.util.apply_text_edits(item.additionalTextEdits, vim.api.nvim_get_current_buf(), encoding)
  end

  local pos = vim.api.nvim_buf_get_extmark_by_id(0, NS, mark, {})
  vim.api.nvim_buf_del_extmark(0, NS, mark)
  row, start_col = pos[1], pos[2]
  vim.api.nvim_win_set_cursor(0, { row + 1, start_col })

  if item.insertTextFormat == 2 then
    expand_lsp_snippet(text)
  else
    local lines = vim.split(text, '\n', { plain = true })
    vim.api.nvim_buf_set_text(0, row, start_col, row, start_col, lines)
    local new_row = row + #lines - 1
    local new_col = (#lines == 1 and start_col or 0) + #lines[#lines]
    vim.api.nvim_win_set_cursor(0, { new_row + 1, new_col })
  end

  -- e.g. Roslyn's roslyn.client.completionComplexEdit (override completions, some imports)
  if client and item.command then
    client:exec_cmd(item.command, { bufnr = vim.api.nvim_get_current_buf() })
  end
end

function M.cancel()
  cancel_pending()
  close_window()
end

function M.setup()
  set_default_highlights()

  local group = vim.api.nvim_create_augroup('MiniComplete', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      -- once per client, not once per buffer it attaches to
      if client and not state.notified_clients[client.id] and client:supports_method('textDocument/completion') then
        state.notified_clients[client.id] = true
        vim.notify('mini_complete: ' .. client.name .. ' attached (indexing may still take a moment)', vim.log.levels.INFO)
      end
    end,
  })

  -- A real typed character ends the post-accept quiet period.
  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = group,
    callback = function() state.just_accepted = false end,
  })

  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    callback = function()
      -- Ignore changes made by accept() itself (and async follow-ups like server commands),
      -- otherwise the popup reopens on the word you just completed.
      if state.just_accepted then return end
      local prefix = get_prefix()
      if #prefix >= 1 then
        schedule_completion()
      else
        cancel_pending()
        close_window()
      end
    end,
  })

  -- Moving the cursor away (arrows, mouse, other line) invalidates start_col/row.
  vim.api.nvim_create_autocmd('CursorMovedI', {
    group = group,
    callback = function()
      if not state.active then return end
      local cur = vim.api.nvim_win_get_cursor(0)
      if cur[1] - 1 ~= state.row or cur[2] < state.start_col then
        cancel_pending()
        close_window()
      end
    end,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = group,
    callback = function()
      state.just_accepted = false
      cancel_pending()
      close_window()
    end,
  })

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

  vim.keymap.set('i', '<F6>', function()
    if state.active then
      M.toggle_docs()
    else
      feed('<F6>')
    end
  end)

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
