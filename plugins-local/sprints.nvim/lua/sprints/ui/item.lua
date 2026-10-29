-- The item buffer: render, refresh, and the actions you can take from inside it.
-- Ported from jira.nvim's issue buffer; the buffer holds a `ref` (four ids) instead of a key.
local config = require("sprints.config")
local items = require("sprints.api.items")
local render = require("sprints.ui.render")
local util = require("sprints.ui.util")

local M = {}

local last_item = {} -- bufnr -> item last rendered (for the raw view)

local function buf_name(ref)
  return ("sprints://%s/%s"):format(ref.project, ref.item)
end

local function ref_of(bufnr)
  return vim.b[bufnr].sprints_ref
end

local function render_into(bufnr, item)
  local lines, highlights = render.render(item)
  util.set_lines(bufnr, lines)
  util.apply_highlights(bufnr, highlights)
  vim.b[bufnr].sprints_ref = item.ref
  vim.b[bufnr].sprints_key = item.key
  vim.b[bufnr].sprints_url = items.browse_url(item.ref, item.no)
  last_item[bufnr] = item
  util.set_readonly(bufnr, true)
end

function M.refresh(bufnr, on_done)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ref = ref_of(bufnr)
  if not ref then
    return vim.notify("sprints.nvim: this buffer is not a Sprints item buffer", vim.log.levels.WARN)
  end
  items.get(ref, function(item, err)
    if not item then
      return util.notify_error("failed to refresh " .. (vim.b[bufnr].sprints_key or ref.item), err)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      render_into(bufnr, item)
    end
    if on_done then
      on_done()
    end
  end)
end

local function after(bufnr, what)
  return function(ok, err)
    if not ok then
      return util.notify_error(what .. " failed", err)
    end
    vim.notify("sprints.nvim: " .. what .. " — done")
    M.refresh(bufnr)
  end
end

function M.change_status(bufnr)
  local ref = ref_of(bufnr)
  local current = (last_item[bufnr] or {}).status_id
  items.statuses(ref, function(list, err)
    if not list then
      return util.notify_error("could not load statuses", err)
    end
    list = vim.tbl_filter(function(s)
      return s.id ~= current
    end, list)
    if #list == 0 then
      return vim.notify("sprints.nvim: no other statuses in this project", vim.log.levels.WARN)
    end
    vim.ui.select(list, {
      prompt = (vim.b[bufnr].sprints_key or "item") .. " → ",
      format_item = function(s)
        return s.name
      end,
    }, function(choice)
      if choice then
        items.set_status(ref, choice.id, after(bufnr, "status → " .. choice.name))
      end
    end)
  end)
end

function M.assign_to_me(bufnr)
  items.assign_to_me(ref_of(bufnr), after(bufnr, "assign to me"))
end

function M.unassign(bufnr)
  items.unassign(ref_of(bufnr), after(bufnr, "unassign"))
end

function M.comment(bufnr)
  require("sprints.ui.comment").open(ref_of(bufnr), vim.b[bufnr].sprints_key, function()
    M.refresh(bufnr)
  end)
end

function M.open_in_browser(bufnr)
  local url = vim.b[bufnr].sprints_url
  if url then
    vim.ui.open(url)
  end
end

--- The raw API payload, for checking field names while the API mapping is being confirmed.
function M.show_raw(bufnr)
  local item = last_item[bufnr]
  if not item then
    return
  end
  M.show_value("sprints://raw/" .. item.ref.item, { details = item.raw_body, decoded_row = item.raw })
end

function M.show_value(name, value)
  local raw_buf = util.named_scratch(name, "lua")
  util.set_lines(raw_buf, vim.split(vim.inspect(value), "\n", { plain = true }))
  util.show(raw_buf)
end

local ACTIONS = {
  { "status", M.change_status, "change status" },
  { "comment", M.comment, "add a comment" },
  { "assign_me", M.assign_to_me, "assign to me (replaces owners)" },
  { "unassign", M.unassign, "remove all owners" },
  { "browser", M.open_in_browser, "open in browser" },
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

function M.open(item, opts)
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch(buf_name(item.ref), "sprints-item")
  if created then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        last_item[bufnr] = nil
      end,
    })
  end
  render_into(bufnr, item)
  setup_keymaps(bufnr)
  util.show(bufnr, opts)
  return bufnr
end

--- Fetch and open. `hint` (e.g. the summary from a list row) only feeds the loading message.
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
