-- Parent / child items (Zoho "sub items"). Ported from jira.nvim's hierarchy.
-- A row carries its parent's id (parentItem); there is no "children of" endpoint, so children
-- are the rows of the item's sprint (listed with subitem=true) whose parent is the item.
-- UNVERIFIED against the live API: that a sub item sits in its parent's sprint, and that
-- item details answer for the parent under the child's sprint (the backlog is tried next).
local async = require("sprints.api.async")
local items = require("sprints.api.items")

local M = {}

--- Rows of `rows` whose parent is `parent_id`, in list (board) order. Pure.
---@param rows table[] normalised items
---@param parent_id string
---@return table[]
function M.children_in(rows, parent_id)
  return vim.tbl_filter(function(it)
    return it.parent_id ~= nil and it.parent_id == tostring(parent_id)
  end, rows)
end

--- cb(parent_item|nil, err). nil, nil = the item has no parent.
---@param item table normalised item (needs .parent_id and .ref)
function M.parent(item, cb)
  if not item.parent_id then
    return async.ok(cb, nil)
  end
  local ref = vim.tbl_extend("force", item.ref, { item = item.parent_id })
  items.get(ref, function(parent, err)
    if parent then
      return cb(parent, nil)
    end
    require("sprints.api.sprints").backlog_id(ref.team, ref.project, function(backlog)
      if not backlog or backlog == ref.sprint then
        return cb(nil, err)
      end
      items.get(vim.tbl_extend("force", ref, { sprint = backlog }), function(p2)
        cb(p2, p2 and nil or err)
      end)
    end)
  end)
end

--- cb(children, err): `item`'s sub items.
function M.children(item, cb)
  items.list({ team = item.ref.team, project = item.ref.project, sprint = item.ref.sprint }, function(rows, err)
    if not rows then
      return cb(nil, err)
    end
    cb(M.children_in(rows, item.ref.item), nil)
  end)
end

return M
