-- Pure rendering: issue data -> buffer lines + highlight specs.
-- No buffer/window APIs are called here, which keeps this trivially
-- unit-testable.
local adf = require("jira.adf")

local M = {}

local META_FIELDS = {
  { key = "status", label = "Status" },
  { key = "assignee", label = "Assignee" },
  { key = "reporter", label = "Reporter" },
  { key = "priority", label = "Priority" },
  { key = "issue_type", label = "Issue Type" },
  { key = "sprint", label = "Sprint" },
}

local function format_date(created)
  if not created then
    return ""
  end
  return created:match("^(%d%d%d%d%-%d%d%-%d%d)") or created
end

--- @param issue table shaped like jira.api.issues.get()'s return value
--- @return string[] lines
--- @return table[] highlights { line, col_start, col_end, hl_group } (0-indexed line)
function M.render(issue)
  local lines = {}
  local highlights = {}

  local function add(line)
    table.insert(lines, line)
    return #lines - 1
  end

  local function hl(line_idx, col_start, col_end, group)
    table.insert(highlights, { line = line_idx, col_start = col_start, col_end = col_end, hl_group = group })
  end

  local heading = "# " .. (issue.key or "?")
  hl(add(heading), 0, #heading, "jiraHeading")

  add("")
  add(issue.summary or "(no summary)")
  add("")

  for _, meta in ipairs(META_FIELDS) do
    local value = issue[meta.key]
    if value ~= nil and value ~= "" then
      local label_text = meta.label .. ":"
      local line_idx = add(string.format("%-14s%s", label_text, value))
      hl(line_idx, 0, #label_text, "jiraLabel")
    end
  end

  add("")
  local desc_heading = "## Description"
  hl(add(desc_heading), 0, #desc_heading, "jiraHeading")
  add("")

  local desc_lines = adf.to_lines(issue.description)
  if #desc_lines == 0 then
    add("(no description)")
  else
    for _, l in ipairs(desc_lines) do
      add(l)
    end
  end

  add("")
  local comments_heading = "## Comments"
  hl(add(comments_heading), 0, #comments_heading, "jiraHeading")
  add("")

  if not issue.comments or #issue.comments == 0 then
    add("(no comments)")
  else
    for i, c in ipairs(issue.comments) do
      local author = c.author or "Unknown"
      local header = author .. " — " .. format_date(c.created)
      local header_idx = add(header)
      hl(header_idx, 0, #author, "jiraCommentAuthor")

      for _, l in ipairs(adf.to_lines(c.body)) do
        add(l)
      end

      if i < #issue.comments then
        add("")
      end
    end
  end

  return lines, highlights
end

return M
