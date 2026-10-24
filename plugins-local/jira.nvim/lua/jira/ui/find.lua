-- :JiraFind — build a JQL query by picking from menus instead of remembering syntax.
-- Each pick re-opens the menu with the JQL-so-far as the prompt, so you also learn what it builds.
local jql = require("jira.jql")
local meta = require("jira.api.meta")
local presets = require("jira.presets")
local util = require("jira.ui.util")

local M = {}

---@class jira.FindItem
---@field label string
---@field run fun(spec: jira.JqlSpec, reopen: fun())

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

---@param title string
---@param query string
local function run(title, query)
  require("jira.ui.list").open(title, query)
end

---@type table<string, string>
local STATUS_LABEL = { open = "not done", todo = "to do", inprogress = "in progress", done = "done" }
---@type table<string, string>
local SPRINT_LABEL = { open = "current sprint", none = "backlog (no sprint)" }

--- Menu rows for the current spec. A spec field that is nil means "any".
---@param spec jira.JqlSpec
---@return jira.FindItem[]
local function items(spec)
  ---@param v string|nil
  local function show(v)
    return v or "any"
  end

  return {
    {
      label = "▶ Run",
      run = function(s)
        run("Find: " .. jql.build(s), jql.build(s))
      end,
    },
    {
      label = "Project      " .. show(spec.project),
      run = function(s, reopen)
        meta.projects(function(list, err)
          if not list then
            util.notify_error("could not list projects", err)
            return reopen()
          end
          ---@type { label: string, value: string|false }[]
          local choices = { { label = "any", value = false } }
          for _, p in ipairs(list) do
            table.insert(choices, { label = ("%-10s %s"):format(p.key, p.name), value = p.key })
          end
          pick("Project", choices, function(v)
            s.project = v or nil
            reopen()
          end)
        end)
      end,
    },
    {
      label = "Assignee     " .. show(spec.assignee),
      run = function(s, reopen)
        pick("Assignee", {
          { label = "anyone", value = false },
          { label = "me", value = "me" },
          { label = "unassigned", value = "unassigned" },
        }, function(v)
          s.assignee = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Status       " .. show(STATUS_LABEL[spec.status or ""]),
      run = function(s, reopen)
        pick("Status", {
          { label = "not done", value = "open" },
          { label = "to do", value = "todo" },
          { label = "in progress", value = "inprogress" },
          { label = "done", value = "done" },
          { label = "any", value = false },
        }, function(v)
          s.status = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Type         " .. show(spec.issue_type),
      run = function(s, reopen)
        meta.issue_types(function(list, err)
          if not list then
            util.notify_error("could not list issue types", err)
            return reopen()
          end
          ---@type { label: string, value: string|false }[]
          local choices = { { label = "any", value = false } }
          for _, t in ipairs(list) do
            table.insert(choices, { label = t, value = t })
          end
          pick("Issue type", choices, function(v)
            s.issue_type = v or nil
            reopen()
          end)
        end)
      end,
    },
    {
      label = "Sprint       " .. show(SPRINT_LABEL[spec.sprint or ""]),
      run = function(s, reopen)
        pick("Sprint", {
          { label = "any", value = false },
          { label = "current sprint", value = "open" },
          { label = "backlog (no sprint)", value = "none" },
        }, function(v)
          s.sprint = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Text         " .. (spec.text and ('"' .. spec.text .. '"') or "any"),
      run = function(s, reopen)
        vim.ui.input({ prompt = "Text contains (empty = any): ", default = s.text or "" }, function(v)
          if v ~= nil then
            s.text = vim.trim(v) ~= "" and vim.trim(v) or nil
          end
          reopen()
        end)
      end,
    },
    {
      label = "Updated      " .. (spec.updated_within and ("last " .. spec.updated_within) or "any time"),
      run = function(s, reopen)
        pick("Updated within", {
          { label = "any time", value = false },
          { label = "last day", value = "1d" },
          { label = "last week", value = "7d" },
          { label = "last 2 weeks", value = "14d" },
          { label = "last month", value = "30d" },
        }, function(v)
          s.updated_within = v or nil
          reopen()
        end)
      end,
    },
    {
      label = "Reported by  " .. (spec.reporter_me and "me" or "anyone"),
      run = function(s, reopen)
        s.reporter_me = not s.reporter_me or nil
        reopen()
      end,
    },
    {
      label = "✎ Edit JQL by hand, then run",
      run = function(s)
        vim.ui.input({ prompt = "JQL: ", default = jql.build(s) }, function(v)
          if v and vim.trim(v) ~= "" then
            run("Search: " .. v, jql.from_freeform(v))
          end
        end)
      end,
    },
    {
      label = "★ Save as preset",
      run = function(s, reopen)
        vim.ui.input({ prompt = "Preset name: " }, function(name)
          name = name and vim.trim(name) or ""
          if name ~= "" then
            local ok, err = presets.save(name, jql.build(s))
            if ok then
              vim.notify(("jira.nvim: saved preset %q — :JiraFind %s"):format(name, name), vim.log.levels.INFO)
            else
              vim.notify("jira.nvim: could not save preset: " .. tostring(err), vim.log.levels.WARN)
            end
          end
          reopen()
        end)
      end,
    },
    {
      label = "☰ Presets…",
      run = function(_, reopen)
        local all = presets.all()
        local names = presets.names()
        if #names == 0 then
          vim.notify("jira.nvim: no presets yet — build a query and pick ★ Save as preset", vim.log.levels.INFO)
          return reopen()
        end
        ---@type { label: string, value: string }[]
        local choices = {}
        for _, n in ipairs(names) do
          table.insert(choices, { label = ("%-20s %s"):format(n, all[n]), value = n })
        end
        pick("Preset", choices, function(n)
          run(n, all[n])
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

--- Open the builder. Starts from "not done" since that's what you want almost every time.
---@param initial jira.JqlSpec|nil
function M.open(initial)
  ---@type jira.JqlSpec
  local spec = initial or { status = "open" }

  local function reopen()
    vim.schedule(function()
      pick("JQL: " .. jql.build(spec), vim.tbl_map(function(item)
        return { label = item.label, value = item }
      end, items(spec)), function(item)
        item.run(spec, reopen)
      end)
    end)
  end
  reopen()
end

--- Run a named preset.
---@param name string
---@return boolean found
function M.run_preset(name)
  local query = presets.all()[name]
  if not query then
    return false
  end
  run(name, query)
  return true
end

return M
