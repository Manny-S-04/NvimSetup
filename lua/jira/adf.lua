-- A small, isolated Atlassian Document Format (ADF) -> plain text
-- converter. This intentionally does NOT implement every ADF node.
-- Unsupported nodes degrade gracefully by rendering their text
-- children (or nothing) instead of erroring.
local M = {}

local render_node -- forward declaration

local function render_marks(text, marks)
  if not marks then
    return text
  end
  for _, mark in ipairs(marks) do
    if mark.type == "strong" then
      text = "**" .. text .. "**"
    elseif mark.type == "em" then
      text = "_" .. text .. "_"
    elseif mark.type == "code" then
      text = "`" .. text .. "`"
    end
  end
  return text
end

local function render_children(content, sep)
  local parts = {}
  for _, child in ipairs(content or {}) do
    table.insert(parts, render_node(child))
  end
  return table.concat(parts, sep or "")
end

render_node = function(node)
  local t = node.type

  if t == "text" then
    return render_marks(node.text or "", node.marks)
  elseif t == "paragraph" then
    return render_children(node.content)
  elseif t == "heading" then
    local level = (node.attrs and node.attrs.level) or 1
    return string.rep("#", level) .. " " .. render_children(node.content)
  elseif t == "hardBreak" then
    return "\n"
  elseif t == "codeBlock" then
    return "```\n" .. render_children(node.content) .. "\n```"
  elseif t == "blockquote" then
    return "> " .. render_children(node.content)
  elseif t == "rule" then
    return "---"
  elseif t == "bulletList" then
    local lines = {}
    for _, item in ipairs(node.content or {}) do
      table.insert(lines, "- " .. render_children(item.content))
    end
    return table.concat(lines, "\n")
  elseif t == "orderedList" then
    local lines = {}
    for i, item in ipairs(node.content or {}) do
      table.insert(lines, i .. ". " .. render_children(item.content))
    end
    return table.concat(lines, "\n")
  elseif t == "listItem" then
    return render_children(node.content)
  elseif t == "mention" then
    return "@" .. ((node.attrs and node.attrs.text) or "user")
  elseif t == "inlineCard" or t == "link" then
    return (node.attrs and (node.attrs.text or node.attrs.url)) or ""
  else
    -- Unsupported node type: degrade gracefully by rendering children
    -- (if any) instead of failing.
    if node.content then
      return render_children(node.content)
    end
    return ""
  end
end

--- Convert an ADF document (or a plain string, for forward-compat) into
--- a list of plain-text lines suitable for a Neovim buffer.
---@param doc table|string|nil
---@return string[] lines
function M.to_lines(doc)
  if doc == nil then
    return {}
  end

  if type(doc) == "string" then
    return vim.split(doc, "\n", { plain = true })
  end

  if type(doc) ~= "table" or doc.type ~= "doc" then
    return {}
  end

  local blocks = {}
  for _, node in ipairs(doc.content or {}) do
    local ok, rendered = pcall(render_node, node)
    if ok then
      table.insert(blocks, rendered)
    end
  end

  local text = table.concat(blocks, "\n\n")
  return vim.split(text, "\n", { plain = true })
end

return M
