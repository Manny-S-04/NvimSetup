-- The item buffer: render, refresh, and the actions you can take from inside it.
-- Ported from jira.nvim's issue buffer. Named by key like jira's (sprints://I22516), so harpoon,
-- :b and :e find it again; the buffer also holds the `ref` (four ids) the API needs.
local config = require("sprints.config")
local items = require("sprints.api.items")
local render = require("sprints.ui.render")
local util = require("sprints.ui.util")
local workspace = require("sprints.api.workspace")

local M = {}

local last_item = {} -- bufnr -> item last rendered
local last_marks = {} -- bufnr -> render marks (comment line ranges)

local function buf_name(key)
  return "sprints://" .. key
end

--- Item key from an item buffer name ("sprints://I22516" -> "I22516"); nil for the other
--- sprints:// buffers (lists, raw, edit, new comment). Also takes the name with its slashes
--- collapsed ("sprints:/I22516"), which is how a path-normalising harpoon config stores it. Pure.
---@param name string
---@return string|nil
function M.key_from_name(name)
  return (name or ""):match("^sprints:[/\\]+([%w%-#]*%d+)$")
end

--- The item an item buffer shows (nil if it isn't one, or it hasn't loaded yet).
function M.item_of(bufnr)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return last_item[bufnr]
end

local function ref_of(bufnr)
  return vim.b[bufnr].sprints_ref
end

local function key_of(bufnr)
  return vim.b[bufnr].sprints_key or "item"
end

local function render_into(bufnr, item)
  local lines, highlights, marks = render.render(item)
  last_marks[bufnr] = marks
  util.set_lines(bufnr, lines)
  util.apply_highlights(bufnr, highlights)
  vim.b[bufnr].sprints_ref = item.ref
  vim.b[bufnr].sprints_key = item.key
  vim.b[bufnr].sprints_url = items.browse_url(item.ref, item.no)
  last_item[bufnr] = item
  util.set_readonly(bufnr, true)
  pcall(function()
    require("sprints.worklist").update(item) -- keep the worklist's status column current
  end)
end

function M.refresh(bufnr, on_done)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ref = ref_of(bufnr)
  if not ref then
    return vim.notify("sprints.nvim: this buffer is not a Sprints item buffer", vim.log.levels.WARN)
  end
  items.get(ref, function(item, err)
    if not item then
      return util.notify_error("failed to refresh " .. key_of(bufnr), err)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      render_into(bufnr, item)
    end
    if on_done then
      on_done()
    end
  end)
end

--- Refresh the item buffer showing `ref`, if one is open (after an edit made elsewhere).
function M.refresh_ref(ref)
  for bufnr, item in pairs(last_item) do
    if vim.api.nvim_buf_is_valid(bufnr) and item.ref.item == ref.item then
      M.refresh(bufnr)
    end
  end
end

--- Callback for an update: report `what` (e.g. "I1: To do → Done") and refresh.
--- An update's callback. A failure may mean the project changed under us (a status, type or
--- field id this session cached was deleted, and Zoho answers that with a 500), so the
--- project caches are dropped: the next attempt offers the current workflow.
local function after(bufnr, what)
  return function(ok, err)
    if not ok then
      require("sprints.api.cache").clear()
      local msg = (err and err.message or "unknown error")
        .. " (project statuses/fields reloaded in case the workflow changed: try again)"
      return util.notify_error(what .. " failed", { message = msg })
    end
    vim.notify("sprints.nvim: " .. what)
    M.refresh(bufnr)
  end
end

function M.change_status(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  items.statuses(ref, function(list, err)
    if not list then
      return util.notify_error("could not load statuses", err)
    end
    list = vim.tbl_filter(function(s)
      return s.id ~= item.status_id
    end, list)
    if #list == 0 then
      return vim.notify("sprints.nvim: no other statuses in this project", vim.log.levels.WARN)
    end
    vim.ui.select(list, {
      prompt = ("%s is %s → "):format(key_of(bufnr), item.status or "?"),
      format_item = function(s)
        return s.name
      end,
    }, function(choice)
      if not choice then
        return
      end
      local what = ("%s: %s → %s"):format(key_of(bufnr), item.status or "?", choice.name)
      -- mandatory custom fields still empty: ask for them and send them with the change,
      -- since Zoho refuses the status change without them
      local missing = require("sprints.api.fields").missing(item, item.field_defs or {})
      if #missing == 0 then
        return items.set_status(ref, choice.id, after(bufnr, what))
      end
      require("sprints.ui.fields").ask_all(missing, ref, function(udf)
        if not udf then
          return vim.notify("sprints.nvim: status change cancelled", vim.log.levels.WARN)
        end
        items.set_status(ref, choice.id, after(bufnr, what), udf)
      end)
    end)
  end)
end

--- Set one of the project's custom fields.
function M.set_field(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  local list = item.custom_fields or {}
  if #list == 0 then
    return vim.notify("sprints.nvim: " .. (item.fields_error or "this project has no custom fields"),
      vim.log.levels.WARN)
  end
  vim.ui.select(list, {
    prompt = key_of(bufnr) .. " field",
    format_item = function(v)
      return ("%s: %s"):format(v.field.name, v.text or (v.field.mandatory and "(empty, required)" or "—"))
    end,
  }, function(v)
    if not v then
      return
    end
    require("sprints.ui.fields").ask(v.field, ref, function(value, label)
      if value ~= nil then
        items.update(ref, { [v.field.udf] = value },
          after(bufnr, ("%s: %s → %s"):format(key_of(bufnr), v.field.name, label or tostring(value))))
      end
    end)
  end)
end

--- The comment under the cursor, or nil (with a message).
local function comment_under_cursor(bufnr)
  local item = last_item[bufnr] or {}
  local i = render.comment_at(last_marks[bufnr], vim.api.nvim_win_get_cursor(0)[1] - 1)
  local c = i and item.comments and item.comments[i]
  if not c then
    vim.notify("sprints.nvim: put the cursor on a comment first", vim.log.levels.WARN)
  end
  return c
end

function M.edit_comment(bufnr)
  local c = comment_under_cursor(bufnr)
  if not c then
    return
  end
  if not c.can_edit then
    return vim.notify("sprints.nvim: Zoho says you can't edit that comment", vim.log.levels.WARN)
  end
  require("sprints.ui.comment").open(ref_of(bufnr), key_of(bufnr), function()
    M.refresh(bufnr)
  end, { note_id = c.id, lines = require("sprints.html").to_lines(c.body) })
end

function M.delete_comment(bufnr)
  local c = comment_under_cursor(bufnr)
  if not c then
    return
  end
  if not c.can_delete then
    return vim.notify("sprints.nvim: Zoho says you can't delete that comment", vim.log.levels.WARN)
  end
  local first = (require("sprints.html").to_lines(c.body)[1] or ""):sub(1, 50)
  if util.confirm(("Delete %s's comment on %s (%s…)?"):format(c.author, key_of(bufnr), first)) then
    items.delete_comment(ref_of(bufnr), c.id, after(bufnr, key_of(bufnr) .. ": comment deleted"))
  end
end

--- Add yourself as an owner, or remove yourself if you already are one. Others are kept.
function M.toggle_me(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.me(ref.team, ref.project, function(me, err)
    if not me then
      return util.notify_error("could not work out who you are", err)
    end
    local mine = vim.tbl_contains(item.owner_ids or {}, me)
    items.toggle_me(ref, item.owner_ids, not mine,
      after(bufnr, ("%s: %s"):format(key_of(bufnr), mine and "removed you as owner" or "added you as owner")))
  end)
end

--- Pick a project user to add or remove as owner (✓ = current owner).
function M.pick_owner(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load users", err)
    end
    local users = {}
    for id, u in pairs(meta.users) do
      table.insert(users, { id = id, name = u.name or id })
    end
    table.sort(users, function(a, b)
      return a.name < b.name
    end)
    local current = item.owner_ids or {}
    vim.ui.select(users, {
      prompt = key_of(bufnr) .. " owners (pick to add/remove)",
      format_item = function(u)
        return (vim.tbl_contains(current, u.id) and "✓ " or "  ") .. u.name
      end,
    }, function(choice)
      if not choice then
        return
      end
      local owners = vim.tbl_filter(function(id)
        return id ~= choice.id
      end, current)
      local adding = #owners == #current
      if adding then
        table.insert(owners, choice.id)
      end
      items.set_owners(ref, current, owners,
        after(bufnr, ("%s: %s %s"):format(key_of(bufnr), adding and "added" or "removed", choice.name)))
    end)
  end)
end

function M.unassign_all(bufnr)
  local item = last_item[bufnr] or {}
  if not item.owner_ids or #item.owner_ids == 0 then
    return vim.notify("sprints.nvim: " .. key_of(bufnr) .. " has no owners")
  end
  if util.confirm(("Remove all owners (%s) from %s?"):format(item.assignee or "", key_of(bufnr))) then
    items.set_owners(ref_of(bufnr), item.owner_ids, {}, after(bufnr, key_of(bufnr) .. ": removed all owners"))
  end
end

--- Pick from one of the project's lookup tables (priority, type) and save it.
local function pick_field(bufnr, tbl_name, order_name, field, label)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load " .. label:lower() .. "s", err)
    end
    local list = {}
    for _, id in ipairs(meta[order_name] or vim.tbl_keys(meta[tbl_name])) do
      local row = meta[tbl_name][id]
      if row and id ~= item[field] then
        table.insert(list, { id = id, name = row.name or id })
      end
    end
    vim.ui.select(list, {
      prompt = ("%s %s is %s → "):format(key_of(bufnr), label:lower(), item[field] and meta[tbl_name][item[field]]
        and meta[tbl_name][item[field]].name or "?"),
      format_item = function(x)
        return x.name
      end,
    }, function(choice)
      if choice then
        items.update(ref, { [field] = choice.id },
          after(bufnr, ("%s: %s → %s"):format(key_of(bufnr), label:lower(), choice.name)))
      end
    end)
  end)
end

function M.pick_priority(bufnr)
  pick_field(bufnr, "priorities", "priority_order", "priority_id", "Priority")
end

function M.edit(bufnr)
  local item = last_item[bufnr]
  if item then
    require("sprints.ui.edit").edit(item, function()
      M.refresh_ref(item.ref)
    end)
  end
end

function M.comment(bufnr)
  require("sprints.ui.comment").open(ref_of(bufnr), key_of(bufnr), function()
    M.refresh(bufnr)
  end)
end

function M.open_in_browser(bufnr)
  local url = vim.b[bufnr].sprints_url
  if url then
    vim.ui.open(url)
  end
end

function M.yank_key(bufnr)
  util.yank(key_of(bufnr), "key")
end

function M.yank_url(bufnr)
  if vim.b[bufnr].sprints_url then
    util.yank(vim.b[bufnr].sprints_url, "link")
  end
end

function M.open_parent(bufnr)
  local item = last_item[bufnr]
  if not item then
    return
  end
  require("sprints.api.hierarchy").parent(item, function(parent, err)
    if err then
      return util.notify_error("could not open " .. key_of(bufnr) .. "'s parent", err)
    end
    if not parent then
      return vim.notify("sprints.nvim: " .. key_of(bufnr) .. " has no parent", vim.log.levels.WARN)
    end
    M.open(parent)
  end)
end

function M.open_children(bufnr)
  local item = last_item[bufnr]
  if item then
    require("sprints.ui.list").open_children(item)
  end
end

function M.work(bufnr)
  local item = last_item[bufnr]
  if item then
    require("sprints.worklist").work(item)
  end
end

function M.worklist_add(bufnr)
  local item = last_item[bufnr]
  if item then
    require("sprints.worklist").add(item)
  end
end

--- The raw API payload, for checking field names while the API mapping is being confirmed.
function M.show_raw(bufnr)
  local item = last_item[bufnr]
  if item then
    M.show_value("sprints://raw/" .. item.ref.item, { details = item.raw_body, decoded_row = item.raw })
  end
end

function M.show_value(name, value)
  local raw_buf = util.named_scratch(name, "lua")
  util.set_lines(raw_buf, vim.split(vim.inspect(value), "\n", { plain = true }))
  util.show(raw_buf)
end

local ACTIONS = {
  { "status", M.change_status, "change status" },
  { "edit", M.edit, "edit title, description, fields (:w saves)" },
  { "comment", M.comment, "add a comment (:w posts)" },
  { "comment_edit", M.edit_comment, "edit the comment under the cursor (:w saves)" },
  { "comment_delete", M.delete_comment, "delete the comment under the cursor (asks first)" },
  { "field", M.set_field, "set a custom field" },
  { "assign_me", M.toggle_me, "add / remove yourself as owner" },
  { "owners", M.pick_owner, "add / remove an owner" },
  { "unassign", M.unassign_all, "remove all owners (asks first)" },
  { "priority", M.pick_priority, "change priority" },
  { "yank_key", M.yank_key, "copy the item key" },
  { "yank_url", M.yank_url, "copy the link" },
  { "browser", M.open_in_browser, "open in browser" },
  { "parent", M.open_parent, "open the parent" },
  { "children", M.open_children, "list child items" },
  { "work", M.work, "worklist = the parent's items (:SprintsWork)" },
  { "worklist_add", M.worklist_add, "add to the worklist" },
  { "raw", M.show_raw, "show the raw API response" },
  { "refresh", M.refresh, "refresh" },
  {
    "close",
    function(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end,
    "close",
  },
}

local function setup_keymaps(bufnr)
  local keys = (config.options.keymaps or {}).item or {}
  local help = { "sprints.nvim item buffer" }
  for _, a in ipairs(ACTIONS) do
    local name, fn, desc = a[1], a[2], a[3]
    if keys[name] then
      vim.keymap.set("n", keys[name], function()
        fn(bufnr)
      end, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: " .. desc })
      table.insert(help, ("  %-6s %s"):format(keys[name], desc))
    end
  end
  if keys.help then
    vim.keymap.set("n", keys.help, function()
      vim.notify(table.concat(help, "\n"))
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: help" })
  end
end

--- One-time setup of a new item buffer.
local function prepare(bufnr)
  -- markdown highlighting for descriptions/comments (parser ships with Neovim);
  -- the plugin's own extmark highlights layer on top
  if not pcall(vim.treesitter.start, bufnr, "markdown") then
    vim.bo[bufnr].syntax = "markdown"
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      last_item[bufnr] = nil
      last_marks[bufnr] = nil
    end,
  })
end

local function set_winbar(bufnr, item)
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    vim.wo[win].winbar = "%#sprintsKey# " .. (item.key or "") .. " %* s status · e edit · c comment · a me · o owners · g? more"
  end
end

function M.open(item, opts)
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch(buf_name(item.key), "sprints-item")
  if created then
    prepare(bufnr)
  end
  render_into(bufnr, item)
  setup_keymaps(bufnr)
  util.show(bufnr, vim.tbl_extend("force", { role = "item" }, opts or {}))
  set_winbar(bufnr, item)
  return bufnr
end

--- BufReadCmd for sprints://<KEY>: Neovim made this buffer from the name alone (harpoon after
--- the buffer was closed, :e sprints://I12, a restored session), so find the item and fill it.
function M.read_cmd(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local key = M.key_from_name(name)
  if not key or last_item[bufnr] then
    return -- not an item buffer, or already filled (nothing to re-read: r refreshes)
  end
  if name ~= buf_name(key) then
    -- A mangled name (sprints:/I12): swap in the real buffer once the caller (e.g. harpoon's
    -- select) has shown this one, then drop it. Scheduled because the caller still uses it.
    util.make_scratch(bufnr, "sprints-item")
    vim.bo[bufnr].bufhidden = "wipe"
    return vim.schedule(function()
      local target = util.find_buf_by_name(buf_name(key))
      if not target then
        target = vim.fn.bufadd(buf_name(key))
        vim.fn.bufload(target) -- runs this function again, for the real name
      end
      for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        vim.api.nvim_win_set_buf(win, target)
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end
  util.setup_highlight_groups()
  util.make_scratch(bufnr, "sprints-item")
  prepare(bufnr)
  util.set_lines(bufnr, { "# " .. key, "", "Loading…" })
  util.set_readonly(bufnr, true)
  if not config.validate() then
    return
  end
  require("sprints.ui.context").project(function(team, project)
    require("sprints.api.find").item(team, project, key, function(found, note)
      if not found then
        return util.notify_error("could not find " .. key, note)
      end
      items.get(found.ref, function(item, err)
        if not item then
          return util.notify_error("failed to fetch " .. key, err)
        end
        if vim.api.nvim_buf_is_valid(bufnr) then
          render_into(bufnr, item)
          setup_keymaps(bufnr)
          set_winbar(bufnr, item)
        end
      end)
    end)
  end)
end

--- Fetch and open. `hint` (e.g. the key from a list row) only feeds the loading message.
function M.open_ref(ref, hint, opts)
  vim.notify("sprints.nvim: loading " .. (hint or ref.item) .. "…")
  items.get(ref, function(item, err)
    if not item then
      return util.notify_error("failed to fetch " .. (hint or ref.item), err)
    end
    M.open(item, opts)
  end)
end

return M
