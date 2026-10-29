-- Pure rendering: item data -> buffer lines + highlight specs (no buffer/window APIs here).
-- Same layout as jira.nvim's issue buffer; HTML bodies instead of ADF.
local html = require("sprints.html")

local M = {}

local META_FIELDS = {
  { key = "status", label = "Status" },
  { key = "assignee", label = "Owners" },
  { key = "reporter", label = "Created by" },
  { key = "priority", label = "Priority" },
  { key = "issue_type", label = "Type" },
  { key = "epic", label = "Epic" },
  { key = "sprint_name", label = "Sprint" },
  { key = "updated", label = "Updated", date = true },
}

--- Zoho sends dates as epoch milliseconds, epoch seconds, or formatted strings.
function M.format_date(v)
  if v == nil or v == "" then
    return ""
  end
  local s = tostring(v)
  local n = tonumber(s)
  if n and #s >= 12 then
    return os.date("%Y-%m-%d", math.floor(n / 1000))
  elseif n and #s >= 9 then
    return os.date("%Y-%m-%d", math.floor(n))
  end
  return s:match("^(%d%d%d%d%-%d%d%-%d%d)") or s
end

function M.render(item)
  local lines, highlights = {}, {}
  local function add(line)
    table.insert(lines, line)
    return #lines - 1
  end
  local function hl(idx, s, e, group)
    table.insert(highlights, { line = idx, col_start = s, col_end = e, hl_group = group })
  end

  local heading = "# " .. (item.key or "?")
  hl(add(heading), 0, #heading, "sprintsHeading")
  add("")
  add(item.summary or "(no name)")
  add("")

  for _, meta in ipairs(META_FIELDS) do
    local value = item[meta.key]
    if meta.date then
      value = M.format_date(value)
    end
    if value ~= nil and value ~= "" then
      local label = meta.label .. ":"
      hl(add(("%-14s%s"):format(label, tostring(value))), 0, #label, "sprintsLabel")
    end
  end

  add("")
  local dh = "## Description"
  hl(add(dh), 0, #dh, "sprintsHeading")
  add("")
  local desc = html.to_lines(item.description)
  if #desc == 0 then
    add("(no description)")
  else
    for _, l in ipairs(desc) do
      add(l)
    end
  end

  add("")
  local ch = "## Comments"
  hl(add(ch), 0, #ch, "sprintsHeading")
  add("")
  if item.comments_error then
    add("(comments unavailable: " .. item.comments_error .. ")")
  elseif not item.comments or #item.comments == 0 then
    add("(no comments)")
  else
    for i, c in ipairs(item.comments) do
      local author = c.author or "Unknown"
      hl(add(author .. " — " .. M.format_date(c.created)), 0, #author, "sprintsCommentAuthor")
      for _, l in ipairs(html.to_lines(c.body)) do
        add(l)
      end
      if i < #item.comments then
        add("")
      end
    end
  end

  return lines, highlights
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

local function pad(s, w)
  return s .. string.rep(" ", math.max(0, w - width(s)))
end

function M.status_hl(category)
  if category == "done" then
    return "sprintsStatusDone"
  elseif category == "indeterminate" then
    return "sprintsStatusProgress"
  end
  return "sprintsStatusTodo"
end

--- @return string[] lines, table[] highlights, table<integer, table> items by 1-based line
function M.render_list(title, items)
  local lines, highlights, by_line = { "# " .. title, "" }, {}, {}
  table.insert(highlights, { line = 0, col_start = 0, col_end = #lines[1], hl_group = "sprintsHeading" })
  if #items == 0 then
    table.insert(lines, "(no items)")
    return lines, highlights, by_line
  end

  local key_w, status_w = 0, 0
  for _, it in ipairs(items) do
    key_w = math.max(key_w, width(it.key or ""))
    status_w = math.max(status_w, width(it.status or ""))
  end
  for _, it in ipairs(items) do
    local key, status = it.key or "?", it.status or ""
    table.insert(lines, pad(key, key_w) .. "  " .. pad(status, status_w) .. "  " .. (it.summary or ""))
    local idx = #lines - 1
    by_line[#lines] = it
    table.insert(highlights, { line = idx, col_start = 0, col_end = #key, hl_group = "sprintsKey" })
    local s = #pad(key, key_w) + 2
    table.insert(highlights, { line = idx, col_start = s, col_end = s + #status, hl_group = M.status_hl(it.status_category) })
  end
  return lines, highlights, by_line
end

return M
