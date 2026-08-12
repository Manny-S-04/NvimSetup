local client = require("jira.api.client")

local M = {}

local KEY_PATTERN = "^[A-Za-z][A-Za-z0-9]+%-%d+$"

--- Validate a Jira issue key like "PROJ-123".
---@param key any
---@return boolean ok
---@return string|nil err
function M.validate_key(key)
  if type(key) ~= "string" or key == "" then
    return false, "issue key must be a non-empty string"
  end
  if not key:match(KEY_PATTERN) then
    return false, ('invalid issue key %q (expected something like PROJ-123)'):format(key)
  end
  return true, nil
end

local FIELDS = "summary,status,assignee,reporter,priority,issuetype,description,comment,sprint,customfield_10020"

local function extract_sprint(fields)
  if type(fields.sprint) == "table" and fields.sprint.name then
    return fields.sprint.name
  end

  local cf = fields.customfield_10020
  if type(cf) == "table" and cf[1] then
    local chosen = cf[1]
    for _, s in ipairs(cf) do
      if type(s) == "table" and s.state == "active" then
        chosen = s
      end
    end
    return type(chosen) == "table" and chosen.name or nil
  end

  return nil
end

local function extract_comments(comment_field)
  local comments = {}
  if type(comment_field) == "table" and type(comment_field.comments) == "table" then
    for _, c in ipairs(comment_field.comments) do
      table.insert(comments, {
        author = (c.author and c.author.displayName) or "Unknown",
        created = c.created,
        body = c.body,
      })
    end
  end
  return comments
end

local function from_response(raw)
  local fields = raw.fields or {}
  return {
    id = raw.id,
    key = raw.key,
    summary = fields.summary,
    status = fields.status and fields.status.name,
    assignee = fields.assignee and fields.assignee.displayName,
    reporter = fields.reporter and fields.reporter.displayName,
    priority = fields.priority and fields.priority.name,
    issue_type = fields.issuetype and fields.issuetype.name,
    sprint = extract_sprint(fields),
    description = fields.description,
    comments = extract_comments(fields.comment),
    raw = raw,
  }
end

--- Fetch a single issue by key.
---@param key string
---@return table|nil issue
---@return table|nil err
function M.get(key)
  local valid, err = M.validate_key(key)
  if not valid then
    return nil, { message = err, type = "validation" }
  end

  local path = ("/rest/api/3/issue/%s"):format(client.uri_encode(key))
  local result, request_err = client.request("GET", path, { query = { fields = FIELDS } })
  if not result then
    return nil, request_err
  end

  return from_response(result.body), nil
end

-- The following are intentionally not implemented in this bootstrap.
-- They exist so the interface shape is stable for future work.

function M.create(_data)
  error("jira.nvim: issues.create is not implemented yet")
end

function M.update(_key, _data)
  error("jira.nvim: issues.update is not implemented yet")
end

function M.delete(_key)
  error("jira.nvim: issues.delete is not implemented yet")
end

function M.add_comment(_key, _comment)
  error("jira.nvim: issues.add_comment is not implemented yet")
end

function M.transition(_key, _transition)
  error("jira.nvim: issues.transition is not implemented yet")
end

return M
