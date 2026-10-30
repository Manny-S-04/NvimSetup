-- Work items (stories, tasks, bugs). Zoho addresses an item by four ids, so the UI passes a
-- `ref` around instead of Jira's single key:
--   ref = { team = "...", project = "...", sprint = "...", item = "..." }
-- (sprint is the backlog id for backlog items).
--
-- CONFIRMED paths (seen in working third-party clients): list items, item details, create,
-- and create's form fields (name, description, projitemtypeid, projpriorityid, users, point).
-- Update takes create's fields + statusid, except owners: newusers=[...] / delusers=[...].
-- UNVERIFIED (best guesses, isolated here so they're one-line fixes): the comment ("notes")
-- endpoints, and that update takes the same field names as create (plus statusid). Field names are matched against several
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
  points = { "point", "points", "storyPoints", "estimationPoint" },
}
M.FIELDS = F

-- Endpoint details that still need confirming against the API docs.
M.ENDPOINTS = {
  list_action = "sprintitems",
  details_action = "details",
  notes_path = "/notes/", -- comments
  notes_list_action = "data",
  note_text_field = "name",
  -- item field -> form field, for update and create
  form_fields = {
    name = "name",
    description = "description",
    status_id = "statusid",
    type_id = "projitemtypeid",
    priority_id = "projpriorityid",
    owner_ids = "users", -- create only: update ignores `users`
    add_owner_ids = "newusers", -- update only
    del_owner_ids = "delusers", -- update only
    points = "point",
  },
  create_only = { owner_ids = true },
  update_only = { add_owner_ids = true, del_owner_ids = true },
  created_id_keys = { "addedItemId", "itemId", "id" },
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
    priority_id = decode.pick(row, F.priority) and tostring(decode.pick(row, F.priority)) or nil,
    issue_type = lookup(meta.types, decode.pick(row, F.type)) or lookup(side.projItemType, decode.pick(row, F.type)),
    type_id = decode.pick(row, F.type) and tostring(decode.pick(row, F.type)) or nil,
    points = decode.pick(row, F.points),
    epic = epic and (lookup(side.epic, epic) or tostring(epic)) or nil,
    created = decode.pick(row, F.created),
    updated = decode.pick(row, F.updated),
    description = decode.pick(row, F.description),
    sprint_name = require("sprints.api.sprints").name_of(ref.team, ref.project, decode.pick(row, F.sprint) or ref.sprint),
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
  local sprints = require("sprints.api.sprints")
  async.all({
    function(done)
      workspace.meta(ref.team, ref.project, done)
    end,
    function(done) -- sprint names for the Sprint: line; failure here mustn't fail the item
      if sprints.name_of(ref.team, ref.project, ref.sprint) then
        return done(true, nil)
      end
      sprints.list(ref.team, ref.project, function()
        done(true, nil)
      end)
    end,
  }, function(res, merr)
    local meta = res and res[1]
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

--- Item fields (keys of ENDPOINTS.form_fields) -> form fields. Unknown keys are an error,
--- not silently dropped, so a typo can't look like a successful save. So is a field the
--- other mode owns (owner_ids on update, add/del_owner_ids on create): Zoho would ignore it.
---@param mode "create"|"update"
function M.to_form(fields, mode)
  local wrong = mode == "create" and M.ENDPOINTS.update_only or M.ENDPOINTS.create_only
  local form = {}
  for k, v in pairs(fields) do
    local name = M.ENDPOINTS.form_fields[k]
    if not name then
      error("sprints.nvim: unknown item field " .. k)
    end
    if wrong[k] then
      error(("sprints.nvim: %s can't be sent on %s"):format(k, mode))
    end
    form[name] = type(v) == "number" and tostring(v) or v
  end
  return form
end

--- Update some fields of an item. `fields` uses item field names (see form_fields).
function M.update(ref, fields, cb)
  local ok, form = pcall(M.to_form, fields, "update")
  if not ok then
    return async.fail(cb, form)
  end
  if next(form) == nil then
    return async.ok(cb, true) -- nothing changed: no request
  end
  client.request("POST", item_path(ref), { form = form }, function(result, err)
    cb(result and true or nil, err)
  end)
end

--- Create an item in a sprint (or the backlog: its id as ref.sprint). cb(new_ref).
function M.create(ref, fields, cb)
  if not (fields.name and fields.name:match("%S")) then
    return async.fail(cb, "an item needs a title")
  end
  local ok, form = pcall(M.to_form, fields, "create")
  if not ok then
    return async.fail(cb, form)
  end
  local where = { team = ref.team, project = ref.project, sprint = ref.sprint }
  client.request("POST", item_path(where), { form = form }, function(result, err)
    if not result then
      return cb(nil, err)
    end
    local id = decode.pick(result.body or {}, M.ENDPOINTS.created_id_keys)
    where.item = id and tostring(id) or nil
    cb(where, nil)
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
  M.update(ref, { status_id = tostring(status_id) }, cb)
end

--- Owners as update wants them: what to add and what to remove, never the full list
--- (update ignores `users`). Pure. Empty sides are left out, so no change = {}.
---@param current string[]|nil owners now
---@param wanted string[] owners after the change
---@return { add_owner_ids: string[]|nil, del_owner_ids: string[]|nil }
function M.owner_changes(current, wanted)
  local function set_of(ids)
    local s = {}
    for _, id in ipairs(ids) do
      s[tostring(id)] = true
    end
    return s
  end
  local now, after = set_of(current or {}), set_of(wanted)
  local add, del = {}, {}
  for _, id in ipairs(wanted) do
    id = tostring(id)
    if not now[id] and not vim.tbl_contains(add, id) then
      table.insert(add, id)
    end
  end
  for _, id in ipairs(current or {}) do
    id = tostring(id)
    if not after[id] and not vim.tbl_contains(del, id) then
      table.insert(del, id)
    end
  end
  return { add_owner_ids = #add > 0 and add or nil, del_owner_ids = #del > 0 and del or nil }
end

--- A copy of `fields` fit for update: owner_ids (the wanted list) becomes add/del diffs
--- against `current_owner_ids`. Pure; other fields pass through.
function M.update_fields(fields, current_owner_ids)
  if fields.owner_ids == nil then
    return fields
  end
  local out = vim.deepcopy(fields)
  out.owner_ids = nil
  return vim.tbl_extend("force", out, M.owner_changes(current_owner_ids, fields.owner_ids))
end

--- Set the owners to `wanted`, given the owners now (`current`).
function M.set_owners(ref, current, wanted, cb)
  M.update(ref, M.update_fields({ owner_ids = wanted }, current), cb)
end

--- Add or remove you as an owner, keeping everyone else (items can have several owners).
---@param current string[] current owner ids
---@param add boolean
function M.toggle_me(ref, current, add, cb)
  workspace.me(ref.team, ref.project, function(me, err)
    if not me then
      return cb(nil, err)
    end
    local owners = vim.tbl_filter(function(id)
      return id ~= me
    end, current or {})
    if add then
      table.insert(owners, me)
    end
    M.set_owners(ref, current, owners, cb)
  end)
end

--- Markdown -> the HTML Zoho's rich-text fields store.
function M.text_to_html(text)
  return require("sprints.markdown").to_html(text)
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
