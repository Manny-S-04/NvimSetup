-- Work items (stories, tasks, bugs). Zoho addresses an item by four ids, so the UI passes a
-- `ref` around instead of Jira's single key:
--   ref = { team = "...", project = "...", sprint = "...", item = "..." }
-- (sprint is the backlog id for backlog items).
--
-- CONFIRMED paths (seen in working third-party clients): list items, item details, create.
-- UNVERIFIED (best guesses, isolated here so they're one-line fixes): the comment ("notes")
-- endpoints and the update-item form field names. Field names are matched against several
-- candidates for the same reason; :SprintsRaw / gR show the real payload.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")
local workspace = require("sprints.api.workspace")

local M = {}

local F = {
  name = { "itemName", "name" },
  no = { "itemNo", "itemno", "itemNumber" },
  status = { "statusId", "statusid", "projItemStatusId", "itemStatusId" },
  type = { "projItemTypeId", "itemTypeId", "projitemtypeid" },
  priority = { "projPriorityId", "priorityId", "projpriorityid" },
  owners = { "ownerIds", "ownerId", "owners", "users", "assignees", "userIds" },
  created_by = { "createdBy", "createdby", "createdById" },
  created = { "createdTime", "createdOn", "createdDate", "createdTimeLong" },
  updated = { "lastModifiedTime", "lastUpdatedTime", "modifiedTime", "lastModifiedTimeLong" },
  description = { "description", "itemDescription", "desc" },
  epic = { "epicId", "epicid" },
  parent = { "parentItemId", "parentId" },
  sprint = { "sprintId", "sprintid" },
}
M.FIELDS = F

-- Endpoint details that still need confirming against the API docs.
M.ENDPOINTS = {
  list_action = "sprintitems",
  details_action = "details",
  notes_path = "/notes/", -- comments
  notes_list_action = "data",
  note_text_field = "name",
  update_status_field = "statusid",
  update_users_field = "users",
}

local function item_path(ref)
  return ("/team/%s/projects/%s/sprints/%s/item/"):format(ref.team, ref.project, ref.sprint)
    .. (ref.item and (ref.item .. "/") or "")
end

--- Done / in progress / to do, from the status name (Zoho statuses are per project, free text).
function M.status_category(name, row)
  local closed = row and decode.pick(row, { "isClosed", "closed", "isCompleted" })
  if closed == true or closed == "true" or closed == 1 then
    return "done"
  end
  local n = (name or ""):lower()
  for _, w in ipairs({ "done", "closed", "complete", "resolved", "released", "cancel" }) do
    if n:find(w, 1, true) then
      return "done"
    end
  end
  for _, w in ipairs({ "progress", "review", "test", "qa", "develop", "doing", "block" }) do
    if n:find(w, 1, true) then
      return "indeterminate"
    end
  end
  return "new"
end

local function lookup(tbl, id)
  if id == nil then
    return nil
  end
  local row = tbl and tbl[tostring(id)]
  return row and row.name or nil
end

--- Display key: Zoho's item number, prefixed when it's a bare number.
function M.display_key(no, id)
  if no == nil then
    return "#" .. tostring(id)
  end
  local s = tostring(no)
  return s:match("^%d+$") and ("I" .. s) or s
end

--- Raw row (+ project meta, + side tables from the same response) -> the plugin's item table.
---@param row table decoded row
---@param ref table { team, project, sprint }
---@param meta table|nil from workspace.meta
---@param side table|nil other JObjs in the same response, keyed by prefix
function M.normalise(row, ref, meta, side)
  meta, side = meta or {}, side or {}
  local status_id = decode.pick(row, F.status)
  local status_row = status_id and (meta.statuses or {})[tostring(status_id)]
  local status = status_row and status_row.name or (side.status and lookup(side.status, status_id)) or status_id

  local owners = {}
  for _, uid in ipairs(decode.id_list(decode.pick(row, F.owners))) do
    table.insert(owners, lookup(meta.users, uid) or lookup(side.user, uid) or uid)
  end

  local function user(id)
    return lookup(meta.users, id) or lookup(side.user, id) or (id and tostring(id))
  end

  local no = decode.pick(row, F.no)
  local epic = decode.pick(row, F.epic)
  return {
    id = row.id,
    key = M.display_key(no, row.id),
    no = no,
    summary = decode.pick(row, F.name),
    status = status and tostring(status) or nil,
    status_id = status_id and tostring(status_id) or nil,
    status_category = M.status_category(status and tostring(status), status_row),
    assignee = #owners > 0 and table.concat(owners, ", ") or nil,
    owner_ids = decode.id_list(decode.pick(row, F.owners)),
    reporter = user(decode.pick(row, F.created_by)),
    priority = lookup(meta.priorities, decode.pick(row, F.priority)) or lookup(side.projPriority, decode.pick(row, F.priority)),
    issue_type = lookup(meta.types, decode.pick(row, F.type)) or lookup(side.projItemType, decode.pick(row, F.type)),
    epic = epic and (lookup(side.epic, epic) or tostring(epic)) or nil,
    created = decode.pick(row, F.created),
    updated = decode.pick(row, F.updated),
    description = decode.pick(row, F.description),
    comments = {},
    ref = {
      team = ref.team,
      project = ref.project,
      sprint = tostring(decode.pick(row, F.sprint) or ref.sprint),
      item = row.id,
    },
    raw = row,
  }
end

--- Items in a sprint (or the backlog: pass its id as ref.sprint).
function M.list(ref, cb)
  workspace.meta(ref.team, ref.project, function(meta, merr)
    if not meta then
      return cb(nil, merr)
    end
    async.pages(item_path({ team = ref.team, project = ref.project, sprint = ref.sprint }),
      { action = M.ENDPOINTS.list_action, subitem = "true" }, "item", function(bodies, err)
        if not bodies then
          return cb(nil, err)
        end
        local rows, side = async.merge(bodies, "item")
        local out = {}
        for _, r in ipairs(rows) do
          table.insert(out, M.normalise(r, ref, meta, side))
        end
        cb(out, nil)
      end)
  end)
end

--- Items in a sprint owned by `user_id`. Filtered client-side: the server-side owner filter
--- (lanefilter) needs board lane ids, which differ per project.
function M.list_owned(ref, user_id, cb)
  M.list(ref, function(items, err)
    if not items then
      return cb(nil, err)
    end
    cb(vim.tbl_filter(function(it)
      return vim.tbl_contains(it.owner_ids, tostring(user_id))
    end, items), nil)
  end)
end

--- Details response -> one row. It's either a JObj with one entry or the fields inline.
local function details_row(body, item_id)
  local rows = decode.rows(body, "item")
  for _, r in ipairs(rows) do
    if r.id == tostring(item_id) then
      return r, rows
    end
  end
  if rows[1] then
    return rows[1], rows
  end
  local inline = vim.tbl_extend("force", {}, body)
  inline.id = tostring(item_id)
  return inline, {}
end

--- @return { author: string, created: any, body: string, id: string }[]
function M.comments(ref, cb)
  workspace.meta(ref.team, ref.project, function(meta, merr)
    if not meta then
      return cb(nil, merr)
    end
    client.request("GET", item_path(ref) .. M.ENDPOINTS.notes_path:gsub("^/", ""),
      { query = { action = M.ENDPOINTS.notes_list_action, index = 1, range = 100 } }, function(result, err)
        if not result then
          return cb(nil, err)
        end
        local rows = workspace.rows_any(result.body or {}, { "notes", "note", "comment", "comments", "itemNotes" })
        local side_users = decode.by_id(result.body or {}, "user")
        local out = {}
        for _, r in ipairs(rows) do
          local author = decode.pick(r, { "createdBy", "addedBy", "ownerId", "userId" })
          table.insert(out, {
            id = r.id,
            author = lookup(meta.users, author) or lookup(side_users, author) or (author and tostring(author)) or "Unknown",
            created = decode.pick(r, { "createdTime", "addedTime", "createdOn", "createdTimeLong" }),
            body = decode.pick(r, { "notes", "note", "comment", "content", "name" }) or "",
          })
        end
        cb(out, nil)
      end)
  end)
end

--- Item with its comments. Comments failing (e.g. while that endpoint is unverified) doesn't
--- fail the item: it's shown with a note instead.
function M.get(ref, cb)
  workspace.meta(ref.team, ref.project, function(meta, merr)
    if not meta then
      return cb(nil, merr)
    end
    client.request("GET", item_path(ref), { query = { action = M.ENDPOINTS.details_action } }, function(result, err)
      if not result then
        return cb(nil, err)
      end
      local row = details_row(result.body or {}, ref.item)
      local _, side = async.merge({ result.body or {} }, "item")
      local item = M.normalise(row, ref, meta, side)
      item.raw_body = result.body
      M.comments(item.ref, function(comments, cerr)
        if comments then
          item.comments = comments
        else
          item.comments_error = cerr and cerr.message or "could not load comments"
        end
        cb(item, nil)
      end)
    end)
  end)
end

local function update(ref, form, cb)
  client.request("POST", item_path(ref), { form = form }, function(result, err)
    cb(result and true or nil, err)
  end)
end

--- Statuses the project defines, in the project's order. Zoho has no per-status transition
--- rules exposed to the API, so every status is offered.
function M.statuses(ref, cb)
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return cb(nil, err)
    end
    local out = {}
    for _, id in ipairs(meta.status_order) do
      table.insert(out, { id = id, name = meta.statuses[id].name })
    end
    cb(out, nil)
  end)
end

function M.set_status(ref, status_id, cb)
  update(ref, { [M.ENDPOINTS.update_status_field] = tostring(status_id) }, cb)
end

function M.set_owners(ref, user_ids, cb)
  update(ref, { [M.ENDPOINTS.update_users_field] = user_ids }, cb)
end

function M.assign_to_me(ref, cb)
  workspace.me(ref.team, ref.project, function(me, err)
    if not me then
      return cb(nil, err)
    end
    M.set_owners(ref, { me }, cb)
  end)
end

function M.unassign(ref, cb)
  M.set_owners(ref, {}, cb)
end

--- Plain text -> the HTML Zoho's rich-text fields store.
function M.text_to_html(text)
  local escaped = text:gsub("\r\n", "\n"):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  local paras = {}
  for para in (escaped .. "\n\n"):gmatch("(.-)\n\n+") do
    if para:match("%S") then
      table.insert(paras, "<div>" .. para:gsub("\n", "<br>") .. "</div>")
    end
  end
  return table.concat(paras)
end

function M.add_comment(ref, text, cb)
  if not text:match("%S") then
    return async.fail(cb, "comment is empty")
  end
  client.request("POST", item_path(ref) .. M.ENDPOINTS.notes_path:gsub("^/", ""),
    { form = { [M.ENDPOINTS.note_text_field] = M.text_to_html(text) } }, function(result, err)
      cb(result and true or nil, err)
    end)
end

function M.browse_url(ref, no)
  local subs = {
    dc = config.domain(),
    team = ref.team,
    project = ref.project,
    sprint = ref.sprint,
    item = ref.item,
    no = no and tostring(no) or "",
  }
  return (config.options.item_url:gsub("{(%w+)}", function(k)
    return subs[k] or ""
  end))
end

return M
