-- Asking for custom field values: one prompt per field, by its kind (pick an option, pick
-- several, pick a user, type a date / number / text). Used by the status change (mandatory
-- fields Zoho would refuse it over) and by "set a field".
local fields = require("sprints.api.fields")
local workspace = require("sprints.api.workspace")

local M = {}

--- "2026-11-05" -> what Zoho's date params take (ISO with offset); anything else is passed
--- through, so a full timestamp also works. Pure.
function M.date_value(s, with_time)
  s = vim.trim(s or "")
  if s:match("^%d%d%d%d%-%d%d%-%d%d$") then
    return s .. "T00:00:00+00:00"
  end
  if with_time and s:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$") then
    return s:gsub(" ", "T") .. ":00+00:00"
  end
  return s
end

local function input(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default }, function(s)
    if s == nil or not s:match("%S") then
      return cb(nil)
    end
    cb(s)
  end)
end

local function pick_many(field, chosen, cb)
  local DONE = { id = "__done", title = "✔ done" }
  local list = vim.list_extend({ DONE }, vim.deepcopy(field.options))
  vim.ui.select(list, {
    prompt = field.name .. " (pick to toggle, then done)",
    format_item = function(o)
      if o == DONE then
        return o.title
      end
      return (vim.tbl_contains(chosen, o.id) and "✓ " or "  ") .. o.title
    end,
  }, function(o)
    if not o then
      return cb(nil)
    end
    if o.id == DONE.id then
      return cb(#chosen > 0 and chosen or nil)
    end
    local rest = vim.tbl_filter(function(id)
      return id ~= o.id
    end, chosen)
    if #rest == #chosen then
      table.insert(rest, o.id)
    end
    pick_many(field, rest, cb)
  end)
end

--- cb(form_value|nil, label|nil). nil = cancelled.
---@param field table from fields.project_fields
---@param ref table item ref (for the user list)
function M.ask(field, ref, cb)
  local kind = fields.kind(field)
  local label = field.name .. (field.mandatory and " (required)" or "")
  if (kind == "one" or kind == "bool") and #field.options > 0 then
    vim.ui.select(field.options, {
      prompt = label,
      format_item = function(o)
        return o.title
      end,
    }, function(o)
      cb(o and fields.encode(field, o.id), o and o.title)
    end)
  elseif kind == "many" and #field.options > 0 then
    pick_many(field, {}, function(ids)
      cb(ids and fields.encode(field, ids), ids and fields.display(field, ids))
    end)
  elseif kind == "user" then
    workspace.meta(ref.team, ref.project, function(meta)
      local users = {}
      for id, u in pairs(meta and meta.users or {}) do
        table.insert(users, { id = id, name = u.name or id })
      end
      table.sort(users, function(a, b)
        return a.name < b.name
      end)
      vim.ui.select(users, {
        prompt = label,
        format_item = function(u)
          return u.name
        end,
      }, function(u)
        cb(u and u.id, u and u.name)
      end)
    end)
  elseif kind == "date" or kind == "datetime" then
    input(label .. (kind == "date" and " [YYYY-MM-DD]: " or " [YYYY-MM-DD HH:MM]: "), nil, function(s)
      cb(s and M.date_value(s, kind == "datetime"), s)
    end)
  else
    -- text / number, and option fields whose options didn't come back (type the option id)
    input(label .. ((kind == "one" or kind == "bool" or kind == "many") and " [option id]: " or ": "), nil,
      function(s)
        cb(s and fields.encode(field, s), s)
      end)
  end
end

--- Ask for each of `list` in turn. cb({ [udf] = form_value }|nil) — nil if any is cancelled.
function M.ask_all(list, ref, cb, acc, i)
  acc, i = acc or {}, i or 1
  local field = list[i]
  if not field then
    return cb(acc)
  end
  M.ask(field, ref, function(value)
    if value == nil then
      return cb(nil)
    end
    acc[field.udf] = value
    M.ask_all(list, ref, cb, acc, i + 1)
  end)
end

return M
