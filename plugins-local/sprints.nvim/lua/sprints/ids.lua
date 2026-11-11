-- The ids behind what you're looking at (team / project / item module / sprint / item), so you
-- never have to dig them out of raw responses: :SprintsIds lists and yanks them, and
-- :SprintsRaw get fills {team} {project} {module} {sprint} {item} in a path from them.
local M = {}

---@class SprintsIds
---@field team string|nil
---@field project string|nil
---@field module string|nil   item module id (comments / custom fields live under it)
---@field sprint string|nil
---@field sprint_name string|nil
---@field item string|nil     Zoho's internal item id
---@field key string|nil      the item number you see (I12065)

local PLACEHOLDERS = { "team", "project", "module", "sprint", "item" }

--- An item's ref (+ its display key) -> the ids it carries. Pure.
---@param ref table|nil { team, project, sprint, item }
---@param key string|nil
---@return SprintsIds
function M.from_ref(ref, key)
  ref = ref or {}
  local function s(v)
    return v ~= nil and v ~= "" and tostring(v) or nil
  end
  return { team = s(ref.team), project = s(ref.project), sprint = s(ref.sprint), item = s(ref.item), key = s(key) }
end

--- Replace {team} {project} {module} {sprint} {item} in `path`. Pure.
--- Returns the filled path, or nil + the first placeholder there's no id for.
---@param path string
---@param ids SprintsIds
---@return string|nil filled
---@return string|nil missing
function M.fill(path, ids)
  for _, name in ipairs(PLACEHOLDERS) do
    if path:find("{" .. name .. "}", 1, true) then
      local v = ids[name]
      if not v then
        return nil, name
      end
      path = path:gsub("{" .. name .. "}", (v:gsub("%%", "%%%%")))
    end
  end
  return path, nil
end

--- `ids` -> { {label, value}, ... } for the ones that are known, in a fixed order. Pure.
---@param ids SprintsIds
---@return { label: string, value: string }[]
function M.rows(ids)
  local out = {}
  local function add(label, value)
    if value then
      table.insert(out, { label = label, value = value })
    end
  end
  add("team (zsoid)", ids.team)
  add("project", ids.project)
  add("item module", ids.module)
  add("sprint" .. (ids.sprint_name and (" (" .. ids.sprint_name .. ")") or ""), ids.sprint)
  add("item" .. (ids.key and (" (" .. ids.key .. ")") or ""), ids.item)
  return out
end

--- The item you're on: the item buffer, else the list row under the cursor. Its ref + key.
local function here()
  local it = require("sprints.ui.item").item_of(0)
  if it then
    return it.ref or vim.b.sprints_ref, it.key or vim.b.sprints_key
  end
  if vim.b.sprints_ref then
    return vim.b.sprints_ref, vim.b.sprints_key
  end
  if vim.bo.filetype == "sprints-list" then
    local row = require("sprints.ui.list").item_under_cursor(0)
    if row then
      return row.ref, row.key
    end
  end
  return nil, nil
end

--- cb(ids): everything known from the current buffer + config, with the item module looked
--- up (cached after the first call). Team / project come from the item when you're on one,
--- else from config / the session's pick.
---@param cb fun(ids: SprintsIds)
function M.collect(cb)
  local ref, key = here()
  local ids = M.from_ref(ref, key)
  local function finish(team, project)
    ids.team, ids.project = ids.team or team, ids.project or project
    if ids.sprint then
      ids.sprint_name = require("sprints.api.sprints").name_of(ids.team, ids.project, ids.sprint)
    end
    require("sprints.api.fields").item_module(ids.team, function(module)
      ids.module = module -- nil when settings.READ is missing; the rest still shows
      cb(ids)
    end)
  end
  if ids.team and ids.project then
    return finish(ids.team, ids.project)
  end
  require("sprints.ui.context").project(finish)
end

return M
