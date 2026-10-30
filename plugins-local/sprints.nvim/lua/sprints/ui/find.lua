-- :SprintsFind — build a query by picking from menus. Ported from jira.nvim's find menu: each
-- pick re-opens the menu with the query-so-far as the prompt. Zoho has no JQL, so where jira
-- offers "Edit JQL by hand" this offers raw text search, and presets store the spec.
local query = require("sprints.api.query")
local presets = require("sprints.presets")
local util = require("sprints.ui.util")
local workspace = require("sprints.api.workspace")

local M = {}

---@generic T
---@param prompt string
---@param choices { label: string, value: T }[]
---@param on_pick fun(value: T)
local function pick(prompt, choices, on_pick)
  vim.ui.select(choices, {
    prompt = prompt,
    format_item = function(c)
      return c.label
    end,
  }, function(choice)
    if choice then
      on_pick(choice.value)
    end
  end)
end

local function progress(done, total)
  if done % 6 == 0 or done == total then
    vim.api.nvim_echo({ { ("sprints.nvim: finding %d/%d sprints"):format(done, total) } }, false, {})
  end
end

--- Open the results of `spec` as a list. `m` in the list narrows to your items on top.
---@param title string
---@param spec sprints.QuerySpec
function M.run(title, spec)
  require("sprints.ui.context").project(function(team, project)
    require("sprints.ui.list").open_with("find/" .. title, title, function(mine_only, cb)
      local s = mine_only and vim.tbl_extend("force", spec, { owner = "me" }) or spec
      query.run(team, project, s, function(found, note)
        if not found then
          return cb(nil, note)
        end
        if note then
          vim.notify("sprints.nvim: " .. note, vim.log.levels.WARN)
        end
        cb(found, nil)
      end, progress)
    end, { project = { team = team, project = project } })
  end)
end

--- Choices from one of the project's lookup tables (statuses, types, priorities).
local function lookup_choices(meta, tbl, order)
  local choices = { { label = "any", value = false } }
  for _, id in ipairs(meta[order] or vim.tbl_keys(meta[tbl] or {})) do
    local row = meta[tbl][id]
    if row then
      table.insert(choices, { label = row.name or id, value = id })
    end
  end
  return choices
end

--- Menu rows for the current spec. A spec field that is nil means "any".
local function items(spec, meta)
  local function name(tbl, id)
    return id and (meta[tbl][id] and meta[tbl][id].name or id) or "any"
  end
  local status = spec.status_id and name("statuses", spec.status_id) or (spec.status and query.STATUS[spec.status]) or "any"
  return {
    {
      label = "▶ Run",
      run = function(s)
        M.run("Find: " .. query.describe(s, meta), vim.deepcopy(s))
      end,
    },
    {
      label = "Where        " .. query.SCOPES[spec.scope or "active"],
      run = function(s, reopen)
        pick("Where", {
          { label = "active sprint", value = "active" },
          { label = "backlog", value = "backlog" },
          { label = "open sprints + backlog", value = "open" },
          { label = "every sprint (slow: one request per sprint)", value = "all" },
        }, function(v)
          s.scope = v
          reopen()
        end)
      end,
    },
    {
      label = "Owner        " .. (spec.owner or "anyone"),
      run = function(s, reopen)
        pick("Owner", {
          { label = "anyone", value = false },
          { label = "me", value = "me" },
          { label = "unassigned", value = "unassigned" },
        }, function(v)
          s.owner = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Status       " .. status,
      run = function(s, reopen)
        local choices = {
          { label = "not done", value = { status = "open" } },
          { label = "to do", value = { status = "todo" } },
          { label = "in progress", value = { status = "inprogress" } },
          { label = "done", value = { status = "done" } },
          { label = "any", value = {} },
        }
        for _, c in ipairs(lookup_choices(meta, "statuses", "status_order")) do
          if c.value then
            table.insert(choices, { label = "exactly: " .. c.label, value = { status_id = c.value } })
          end
        end
        pick("Status", choices, function(v)
          s.status, s.status_id = v.status, v.status_id
          reopen()
        end)
      end,
    },
    {
      label = "Type         " .. name("types", spec.type_id),
      run = function(s, reopen)
        pick("Type", lookup_choices(meta, "types"), function(v)
          s.type_id = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Priority     " .. name("priorities", spec.priority_id),
      run = function(s, reopen)
        pick("Priority", lookup_choices(meta, "priorities", "priority_order"), function(v)
          s.priority_id = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Text         " .. (spec.text and ('"' .. spec.text .. '"') or "any"),
      run = function(s, reopen)
        vim.ui.input({ prompt = "Title or item number contains (empty = any): ", default = s.text or "" }, function(v)
          if v ~= nil then
            s.text = vim.trim(v) ~= "" and vim.trim(v) or nil
          end
          reopen()
        end)
      end,
    },
    {
      label = "Created by   " .. (spec.created_by_me and "me" or "anyone"),
      run = function(s, reopen)
        s.created_by_me = not s.created_by_me or nil
        reopen()
      end,
    },
    {
      label = "★ Save as preset",
      run = function(s, reopen)
        vim.ui.input({ prompt = "Preset name: " }, function(n)
          n = n and vim.trim(n) or ""
          if n ~= "" then
            local ok, err = presets.save(n, s)
            if ok then
              vim.notify(("sprints.nvim: saved preset %q — :SprintsFind %s"):format(n, n))
            else
              vim.notify("sprints.nvim: could not save preset: " .. tostring(err), vim.log.levels.WARN)
            end
          end
          reopen()
        end)
      end,
    },
    {
      label = "☰ Presets…",
      run = function(_, reopen)
        local all, names = presets.all(), presets.names()
        if #names == 0 then
          vim.notify("sprints.nvim: no presets yet — build a query and pick ★ Save as preset")
          return reopen()
        end
        local choices = {}
        for _, n in ipairs(names) do
          table.insert(choices, { label = ("%-20s %s"):format(n, query.describe(all[n], meta)), value = n })
        end
        pick("Preset", choices, function(n)
          M.run(n, all[n])
        end)
      end,
    },
    {
      label = "✕ Reset",
      run = function(s, reopen)
        for k in pairs(s) do
          s[k] = nil
        end
        s.status = "open"
        reopen()
      end,
    },
  }
end

--- Open the builder. Starts from "not done" in the active sprint, like jira's "not done".
---@param initial sprints.QuerySpec|nil
function M.open(initial)
  local spec = initial or { status = "open" }
  require("sprints.ui.context").project(function(team, project)
    workspace.meta(team, project, function(meta, err)
      if not meta then
        return util.notify_error("could not load project fields", err)
      end
      local function reopen()
        vim.schedule(function()
          pick("Find: " .. query.describe(spec, meta), vim.tbl_map(function(item)
            return { label = item.label, value = item }
          end, items(spec, meta)), function(item)
            item.run(spec, reopen)
          end)
        end)
      end
      reopen()
    end)
  end)
end

--- Run a named preset.
---@param name string
---@return boolean found
function M.run_preset(name)
  local spec = presets.all()[name]
  if not spec then
    return false
  end
  M.run(name, spec)
  return true
end

return M
