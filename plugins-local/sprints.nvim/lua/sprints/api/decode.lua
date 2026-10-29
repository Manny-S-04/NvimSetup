-- Zoho Sprints doesn't return arrays of objects. A list endpoint returns, per resource:
--   <x>Ids   = { "id1", "id2" }                  order
--   <x>JObj  = { id1 = { "Name", 3, ... } }      positional values per id
--   <x>_prop = { itemName = 0, itemNo = 1, ... } field name -> 0-based position
-- Pure functions only: this turns that into { { id = "id1", itemName = "Name", ... } }.
-- The prop map's exact key spelling varies between endpoints, so several are tried.
local M = {}

local function prop_map(body, prefix)
  for _, k in ipairs({ prefix .. "_prop", prefix .. "prop", prefix .. "Prop", prefix .. "_props", prefix .. "Props" }) do
    if type(body[k]) == "table" then
      return body[k]
    end
  end
  return nil
end

--- Ids in the server's order, then any JObj entries the order list didn't mention (sorted, so
--- the result is stable). Without that second pass, an order list that doesn't line up with
--- the JObj keys would silently drop rows.
local function ordered_ids(body, prefix, jobj)
  local out, used = {}, {}
  local ids = body[prefix .. "Ids"] or body[prefix .. "ids"]
  if type(ids) == "table" then
    for _, id in ipairs(ids) do
      local k = tostring(id)
      if jobj[k] ~= nil and not used[k] then
        used[k] = true
        table.insert(out, k)
      end
    end
  end
  local rest = {}
  for id in pairs(jobj) do
    if not used[id] then
      table.insert(rest, id)
    end
  end
  table.sort(rest)
  return vim.list_extend(out, rest)
end

--- One positional row -> named table.
local function name_row(id, values, props)
  local row = { id = id }
  if type(values) ~= "table" then
    row.name = values -- some lookups are plain { id = "Name" }
    return row
  end
  if props then
    for field, idx in pairs(props) do
      local i = tonumber(idx)
      if i then
        row[field] = values[i + 1] -- 0-based on the wire
      end
    end
  end
  if row.name == nil and type(values[1]) ~= "table" then
    row.name = values[1] -- every Zoho JObj puts the display name first
  end
  row.id = id -- the JObj key is the id; a prop literally named "id" must not replace it
  return row
end

--- @param body table decoded response
--- @param prefix string e.g. "item", "sprint", "user", "status"
--- @return table[] rows (empty if the body has no such resource)
function M.rows(body, prefix)
  if type(body) ~= "table" then
    return {}
  end
  local jobj = body[prefix .. "JObj"] or body[prefix .. "jobj"]
  if type(jobj) ~= "table" then
    return {}
  end
  local props = prop_map(body, prefix)
  local out = {}
  for _, id in ipairs(ordered_ids(body, prefix, jobj)) do
    table.insert(out, name_row(id, jobj[id], props))
  end
  return out
end

--- rows() keyed by id.
function M.by_id(body, prefix)
  local out = {}
  for _, row in ipairs(M.rows(body, prefix)) do
    out[row.id] = row
  end
  return out
end

--- First non-empty value among candidate field names (field names differ across endpoints).
function M.pick(row, names)
  for _, n in ipairs(names) do
    local v = row[n]
    if v ~= nil and v ~= "" and v ~= vim.NIL then
      return v
    end
  end
  return nil
end

--- A field that should hold a list of ids, which Zoho sends as an array, a JSON string,
--- a comma-separated string or a single id.
function M.id_list(v)
  if v == nil or v == "" or v == vim.NIL then
    return {}
  end
  if type(v) == "table" then
    local out = {}
    for _, x in ipairs(v) do
      table.insert(out, tostring(x))
    end
    return out
  end
  local s = tostring(v)
  if s:match("^%s*%[") then
    local ok, decoded = pcall(vim.json.decode, s)
    if ok and type(decoded) == "table" then
      return M.id_list(decoded)
    end
  end
  local out = {}
  for part in s:gmatch("[^,%s]+") do
    table.insert(out, part)
  end
  return out
end

return M
