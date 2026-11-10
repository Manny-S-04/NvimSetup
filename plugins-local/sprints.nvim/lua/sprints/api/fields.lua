-- Custom item fields (Zoho "UDF_*" columns): their definitions, which ones a project's layout
-- shows and requires, and how their values read and are sent.
--
-- CONFIRMED from Zoho's API reference (apidoc.html):
--   modules:     GET  /team/T/settings/customization/modules/?action=data&index=1&range=50
--                     (settings.READ) -> custommoduleJObj; the item module is moduleName "item"
--                     (entityType 3). Comments live under that module id too.
--   definitions: GET  /team/T/settings/customization/modules/{module}/fields/?action=data
--                     (settings.READ) -> customfieldJObj: fieldName, udfName, fieldType,
--                     optionGroups (optgroup_prop: groupName, options; options_prop: optionTitle)
--                     Live-confirmed 2026-11-10: optionGroups = { groupIds, groupJObj = {
--                     [gid] = { groupName, { optionIds, optionJObj = { [oid] = { optionTitle,
--                     userId } } } } } }; vim.empty_dict() on fields without options.
--   per project: GET  /team/T/projects/P/modules/{module}/?action=formfields (projects.READ)
--                     -> sectionVSfields[section].fieldJObj[fieldId]: sequence, isMandatory, ...
--   values:      item details' item_prop carries the UDF_* columns; update takes UDF_<n>=value
--                     (picklist / radio / boolean / user picklist = option or user id,
--                     multi picklist / checkbox = JSON array).
-- options() reads that grouped shape directly (keeping Zoho's order) and falls back to a loose
-- walk for anything else (fieldOption). Zoho has no per-status rules in the API: "mandatory" is the
-- layout's flag, and the status prompt asks for any mandatory field that is still empty.
local async = require("sprints.api.async")
local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")

local M = {}

local module_cache = {} -- team -> item module id
local fields_cache = {} -- "team/project" -> fields

function M.clear_cache()
  module_cache, fields_cache = {}, {}
end

--- Modules response -> the item module's id, or nil. Pure.
function M.parse_item_module(body)
  for _, r in ipairs(decode.rows(body or {}, "custommodule")) do
    if r.moduleName == "item" or tonumber(r.entityType) == 3 then
      return r.id
    end
  end
  return nil
end

--- cb(module_id, err). config.item_module_id skips the request.
function M.item_module(team, cb)
  local fixed = config.options.item_module_id
  if fixed and fixed ~= "" then
    return async.ok(cb, tostring(fixed))
  end
  if module_cache[team] then
    return async.ok(cb, module_cache[team])
  end
  client.request("GET", ("/team/%s/settings/customization/modules/"):format(team),
    { query = { action = "data", index = 1, range = 50 } }, function(result, err)
      if not result then
        return cb(nil, err)
      end
      local id = M.parse_item_module(result.body)
      if not id then
        return cb(nil, { message = "no item module in the modules list (set item_module_id in setup)" })
      end
      module_cache[team] = id
      cb(id, nil)
    end)
end

local function is_id(k)
  return type(k) == "string" and k:match("^%d+$") ~= nil
end

--- The confirmed optionGroups shape -> { {id, title}, ... } in Zoho's order (groupIds, then
--- each group's optionIds), or nil when v isn't that shape. Pure.
---@param v any
---@param group_prop table<string, integer> optgroup_prop from the same response
---@param option_prop table<string, integer> options_prop from the same response
---@return { id: string, title: string }[]|nil
local function grouped_options(v, group_prop, option_prop)
  if type(v) ~= "table" or type(v.groupJObj) ~= "table" or type(v.groupIds) ~= "table" then
    return nil
  end
  local options_at = (tonumber(group_prop.options) or 1) + 1
  local title_at = (tonumber(option_prop.optionTitle) or 0) + 1
  local out, seen = {}, {}
  for _, gid in ipairs(v.groupIds) do
    local group = v.groupJObj[gid]
    local opts = type(group) == "table" and group[options_at] or nil
    if type(opts) == "table" and type(opts.optionJObj) == "table" then
      for _, oid in ipairs(opts.optionIds or {}) do
        local o = opts.optionJObj[oid]
        local title = type(o) == "table" and o[title_at] or nil
        if type(title) == "string" and not seen[oid] then
          seen[oid] = true
          table.insert(out, { id = tostring(oid), title = title })
        end
      end
    end
  end
  return out
end

--- optionGroups / fieldOption -> { {id, title}, ... }. The confirmed grouped shape keeps Zoho's
--- order; anything else is walked loosely: { [id] = { "Title", ... } }, { [id] = "Title" }, and
--- lists / groups ({ "Group", { [id] = {...} } }) wrapping those, sorted by id. Pure.
---@param body table|nil the definitions response, for optgroup_prop / options_prop
function M.options(v, body)
  body = type(body) == "table" and body or {}
  local grouped = grouped_options(v, body.optgroup_prop or {}, body.options_prop or {})
  if grouped then
    return grouped
  end
  local out, seen = {}, {}
  local function walk(node, depth)
    if type(node) ~= "table" or depth > 6 then
      return
    end
    local keys = vim.tbl_keys(node)
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
      local val = node[k]
      -- { "Group", { ...options } } is a group to descend into, not an option titled "Group".
      local is_group = type(val) == "table" and type(val[2]) == "table"
      local title = type(val) == "string" and val
        or (type(val) == "table" and not is_group and type(val[1]) == "string" and val[1])
        or (type(val) == "table" and type(val.optionTitle) == "string" and val.optionTitle)
      if is_id(k) and title then
        if not seen[k] then
          seen[k] = true
          table.insert(out, { id = k, title = title })
        end
      else
        walk(val, depth + 1)
      end
    end
  end
  walk(v, 0)
  return out
end

--- Definitions response -> { [field_id] = { id, name, udf, type, options } }. Pure.
function M.parse_definitions(body)
  local out = {}
  for _, r in ipairs(decode.rows(body or {}, "customfield")) do
    local opts = M.options(r.optionGroups, body)
    if #opts == 0 then
      opts = M.options(r.fieldOption, body)
    end
    out[r.id] = {
      id = r.id,
      name = r.fieldName or r.id,
      udf = type(r.udfName) == "string" and r.udfName or nil,
      type = r.fieldType,
      options = opts,
    }
  end
  return out
end

--- formfields response -> { [field_id] = { sequence, mandatory } } (fields the project's
--- layout shows). Pure.
function M.parse_layout(body)
  body = body or {}
  local prop = body.customfield_prop or {}
  local function at(row, name, default)
    local i = tonumber(prop[name])
    local v = i and type(row) == "table" and row[i + 1]
    if v == nil or v == vim.NIL then
      return default
    end
    return v
  end
  local out = {}
  local sec_order = 0
  for _, sec in pairs(body.sectionVSfields or {}) do
    sec_order = sec_order + 1
    for id, row in pairs(type(sec) == "table" and sec.fieldJObj or {}) do
      local m = at(row, "isMandatory", false)
      out[tostring(id)] = {
        sequence = tonumber(at(row, "sequence", 0)) or 0,
        mandatory = m == true or m == "true" or m == 1,
      }
    end
  end
  return out
end

--- Definitions + layout -> the project's custom (UDF_*) fields in layout order. Pure.
function M.merge(defs, layout)
  local out = {}
  for id, l in pairs(layout or {}) do
    local d = defs[id]
    if d and d.udf and d.udf:match("^UDF_") then
      table.insert(out, vim.tbl_extend("force", d, l))
    end
  end
  table.sort(out, function(a, b)
    if a.sequence ~= b.sequence then
      return a.sequence < b.sequence
    end
    return a.id < b.id
  end)
  return out
end

--- cb(fields, err): the project's custom item fields, cached per project.
function M.project_fields(team, project, cb)
  local key = team .. "/" .. project
  if fields_cache[key] then
    return async.ok(cb, fields_cache[key])
  end
  M.item_module(team, function(module, merr)
    if not module then
      return cb(nil, merr)
    end
    async.all({
      function(done)
        client.request("GET", ("/team/%s/settings/customization/modules/%s/fields/"):format(team, module),
          { query = { action = "data" } }, done)
      end,
      function(done)
        client.request("GET", ("/team/%s/projects/%s/modules/%s/"):format(team, project, module),
          { query = { action = "formfields" } }, done)
      end,
    }, function(res, err)
      if not res then
        return cb(nil, err)
      end
      local list = M.merge(M.parse_definitions(res[1].body), M.parse_layout(res[2].body))
      fields_cache[key] = list
      cb(list, nil)
    end)
  end)
end

--- How a field is asked for: "one" (pick an option), "many", "user", "date", "datetime",
--- "number", "bool" or "text". From the UDF column family. Pure.
function M.kind(field)
  local fam = (field.udf or ""):match("^UDF_(%a+)") or ""
  if fam == "PKL" or fam == "RADIO" then
    return "one"
  elseif fam == "MULTIPKL" or fam == "CHKBOX" then
    return "many"
  elseif fam == "USERPKL" then
    return "user"
  elseif fam == "BOOLEAN" then
    return "bool"
  elseif fam == "DATE" then
    return "date"
  elseif fam == "DATETIME" then
    return "datetime"
  elseif fam == "LONG" or fam == "DOUBLE" then
    return "number"
  end
  return "text"
end

local function empty(v)
  return v == nil or v == vim.NIL or v == "" or v == "-1" or v == -1
    or (type(v) == "table" and next(v) == nil)
end

--- A raw UDF value -> display text, or nil when empty. Pure.
---@param users table|nil meta.users ({ [id] = { name } })
function M.display(field, raw, users)
  if empty(raw) then
    return nil
  end
  local titles = {}
  for _, o in ipairs(field.options or {}) do
    titles[o.id] = o.title
  end
  local ids = type(raw) == "table" and raw or decode.id_list(raw)
  local k = M.kind(field)
  if k == "one" or k == "many" or k == "bool" or k == "user" then
    local parts = {}
    for _, id in ipairs(ids) do
      id = tostring(id)
      local u = users and users[id]
      table.insert(parts, titles[id] or (u and u.name) or id)
    end
    return table.concat(parts, ", ")
  elseif k == "date" or k == "datetime" then
    return require("sprints.ui.render").format_date(raw, k == "datetime")
  elseif k == "text" then
    local lines = require("sprints.html").to_lines(tostring(raw))
    return table.concat(lines, " ")
  end
  return tostring(raw)
end

--- The item's custom fields as { field, raw, text } in layout order (empty ones included,
--- text = nil). Pure.
function M.values(item, fields, users)
  local out = {}
  local row = item.raw or {}
  for _, f in ipairs(fields or {}) do
    local raw = row[f.udf]
    table.insert(out, { field = f, raw = raw, text = M.display(f, raw, users) })
  end
  return out
end

--- Mandatory fields the item leaves empty. Pure.
function M.missing(item, fields)
  local out = {}
  for _, v in ipairs(M.values(item, fields)) do
    if v.field.mandatory and v.text == nil then
      table.insert(out, v.field)
    end
  end
  return out
end

--- A chosen value -> the form value update takes. Pure.
---@param value string|string[]
function M.encode(field, value)
  if M.kind(field) == "many" then
    return vim.json.encode(type(value) == "table" and value or { value })
  end
  return type(value) == "table" and tostring(value[1]) or tostring(value)
end

return M
