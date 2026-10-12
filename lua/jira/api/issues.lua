-- Jira issue resources. Every function takes an optional trailing callback:
--   with it:    async, callback(value, err) runs on the main loop
--   without it: blocking, returns value, err
local client = require("jira.api.client")
local config = require("jira.config")

local M = {}

local KEY_PATTERN = "^[A-Za-z][A-Za-z0-9_]*%-%d+$"

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

local function api(path)
  return ("/rest/api/%s%s"):format(config.api_version(), path)
end

--- Run a request and map its result, in either sync or async style.
local function call(method, path, opts, transform, cb)
  if cb then
    client.request(method, path, opts, function(result, err)
      if not result then
        return cb(nil, err)
      end
      cb(transform(result), nil)
    end)
    return
  end
  local result, err = client.request(method, path, opts)
  if not result then
    return nil, err
  end
  return transform(result), nil
end

local function fail(cb, err)
  if cb then
    vim.schedule(function()
      cb(nil, err)
    end)
    return
  end
  return nil, err
end

-- customfield_10020 is the Sprint field on Jira Cloud. On Server/DC the sprint field id varies
-- per instance, and its value is a string like "com.atlassian...Sprint@1a2b[id=1,name=Sprint 7,...]".
local FIELDS = "summary,status,assignee,reporter,priority,issuetype,description,comment,sprint,customfield_10020,updated"
local LIST_FIELDS = "summary,status,assignee,priority,issuetype,updated"

local function sprint_name(s)
  if type(s) == "table" then
    return s.name, s.state
  elseif type(s) == "string" then
    return s:match("name=([^,%]]+)"), s:match("state=([^,%]]+)")
  end
end

local function extract_sprint(fields)
  local direct = sprint_name(fields.sprint)
  if direct then
    return direct
  end

  local cf = fields.customfield_10020
  if type(cf) == "table" and cf[1] then
    local chosen = sprint_name(cf[1])
    for _, s in ipairs(cf) do
      local name, state = sprint_name(s)
      if state and state:lower() == "active" then
        chosen = name
      end
    end
    return chosen
  end

  return nil
end

local function extract_comments(comment_field)
  local comments = {}
  if type(comment_field) == "table" and type(comment_field.comments) == "table" then
    for _, c in ipairs(comment_field.comments) do
      table.insert(comments, {
        author = (type(c.author) == "table" and c.author.displayName) or "Unknown",
        created = c.created,
        body = c.body,
      })
    end
  end
  return comments
end

local function name_of(v, key)
  return type(v) == "table" and v[key or "name"] or nil
end

local function from_response(raw)
  local fields = raw.fields or {}
  return {
    id = raw.id,
    key = raw.key,
    summary = fields.summary,
    status = name_of(fields.status),
    status_category = type(fields.status) == "table" and name_of(fields.status.statusCategory, "key") or nil,
    assignee = name_of(fields.assignee, "displayName"),
    reporter = name_of(fields.reporter, "displayName"),
    priority = name_of(fields.priority),
    issue_type = name_of(fields.issuetype),
    sprint = extract_sprint(fields),
    updated = fields.updated,
    description = fields.description,
    comments = extract_comments(fields.comment),
    raw = raw,
  }
end

--- Fetch a single issue by key.
function M.get(key, cb)
  local valid, err = M.validate_key(key)
  if not valid then
    return fail(cb, { message = err, type = "validation" })
  end

  local path = api(("/issue/%s"):format(client.uri_encode(key)))
  return call("GET", path, { query = { fields = FIELDS } }, function(result)
    return from_response(result.body)
  end, cb)
end

--- Search issues with JQL. Returns a list of issue tables (lighter than get()).
function M.search(jql, cb)
  local query = { jql = jql, fields = LIST_FIELDS, maxResults = config.options.max_results or 50 }
  -- Cloud retired GET /rest/api/3/search in favour of /search/jql.
  local path = config.is_cloud() and api("/search/jql") or api("/search")
  return call("GET", path, { query = query }, function(result)
    local out = {}
    for _, raw in ipairs((result.body or {}).issues or {}) do
      table.insert(out, from_response(raw))
    end
    return out
  end, cb)
end

--- Transitions available from the issue's current status.
--- @return { id: string, name: string, to: string|nil }[]
function M.transitions(key, cb)
  local path = api(("/issue/%s/transitions"):format(client.uri_encode(key)))
  return call("GET", path, {}, function(result)
    local out = {}
    for _, t in ipairs((result.body or {}).transitions or {}) do
      table.insert(out, { id = t.id, name = t.name, to = name_of(t.to) })
    end
    return out
  end, cb)
end

function M.transition(key, transition_id, cb)
  local path = api(("/issue/%s/transitions"):format(client.uri_encode(key)))
  return call("POST", path, { body = { transition = { id = tostring(transition_id) } } }, function()
    return true
  end, cb)
end

--- Plain text -> Atlassian Document Format (Cloud comment bodies must be ADF).
--- Blank lines separate paragraphs; single newlines become hard breaks.
function M.text_to_adf(text)
  local doc = { type = "doc", version = 1, content = {} }
  local normalized = text:gsub("\r\n", "\n")
  for para in (normalized .. "\n\n"):gmatch("(.-)\n\n+") do
    if para:match("%S") then
      local content = {}
      local lines = vim.split(para, "\n", { plain = true })
      for i, line in ipairs(lines) do
        if line ~= "" then
          table.insert(content, { type = "text", text = line })
        end
        if i < #lines then
          table.insert(content, { type = "hardBreak" })
        end
      end
      table.insert(doc.content, { type = "paragraph", content = content })
    end
  end
  return doc
end

function M.add_comment(key, text, cb)
  if not text:match("%S") then
    return fail(cb, { message = "comment is empty", type = "validation" })
  end
  local path = api(("/issue/%s/comment"):format(client.uri_encode(key)))
  local body = { body = config.is_cloud() and M.text_to_adf(text) or text }
  return call("POST", path, { body = body }, function()
    return true
  end, cb)
end

local myself_cache = nil

--- The authenticated user. Cached for the session.
function M.myself(cb)
  if myself_cache then
    if cb then
      vim.schedule(function()
        cb(myself_cache, nil)
      end)
      return
    end
    return myself_cache, nil
  end
  return call("GET", api("/myself"), {}, function(result)
    myself_cache = result.body
    return myself_cache
  end, cb)
end

--- Assign the issue to the authenticated user.
--- Cloud identifies users by accountId; Server/DC by username.
function M.assign_to_me(key, cb)
  local path = api(("/issue/%s/assignee"):format(client.uri_encode(key)))
  local function body_for(me)
    if config.is_cloud() then
      return { accountId = me.accountId }
    end
    return { name = me.name }
  end

  if cb then
    M.myself(function(me, err)
      if not me then
        return cb(nil, err)
      end
      call("PUT", path, { body = body_for(me) }, function()
        return true
      end, cb)
    end)
    return
  end

  local me, err = M.myself()
  if not me then
    return nil, err
  end
  return call("PUT", path, { body = body_for(me) }, function()
    return true
  end)
end

--- Web URL for an issue.
function M.browse_url(key)
  return (config.options.url or ""):gsub("/+$", "") .. "/browse/" .. key
end

return M
