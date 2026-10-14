-- <leader>? : fuzzy-search every mapping by what it does, then show the keys.
-- Type "definition" -> "<F12>  Go to definition (F12)". <CR> tells you the keys (doesn't run them);
-- <C-r> runs the mapping instead.
local M = {}

local MODES = { n = "normal", v = "visual", x = "visual", i = "insert" }

local function pretty(lhs)
  lhs = lhs:gsub("^" .. vim.pesc(vim.g.mapleader or "\\"), "<leader>")
  return lhs
end

local function collect()
  local seen, items = {}, {}
  for mode in pairs(MODES) do
    local maps = vim.list_extend(vim.api.nvim_buf_get_keymap(0, mode), vim.api.nvim_get_keymap(mode))
    for _, m in ipairs(maps) do
      local what = m.desc or (m.rhs ~= "" and m.rhs) or nil
      -- Skip <Plug> plumbing and undescribed Lua callbacks: nothing to search by.
      if what and not m.lhs:match("^<Plug>") then
        local key = pretty(m.lhs)
        local id = MODES[mode] .. key
        if not seen[id] then
          seen[id] = true
          table.insert(items, { lhs = key, raw = m.lhs, mode = mode, desc = what })
        end
      end
    end
  end
  table.sort(items, function(a, b) return a.desc:lower() < b.desc:lower() end)
  return items
end

function M.open()
  local pickers, finders = require("telescope.pickers"), require("telescope.finders")
  local conf = require("telescope.config").values
  local actions, state = require("telescope.actions"), require("telescope.actions.state")

  pickers.new(require("telescope.themes").get_dropdown({ previewer = false }), {
    prompt_title = "What key does…",
    finder = finders.new_table({
      results = collect(),
      entry_maker = function(it)
        local text = string.format("%-14s %-7s %s", it.lhs, MODES[it.mode], it.desc)
        return { value = it, display = text, ordinal = it.desc .. " " .. it.lhs }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        local it = state.get_selected_entry().value
        actions.close(bufnr)
        vim.notify(string.format("%s  →  %s (%s mode)", it.desc, it.lhs, MODES[it.mode]))
      end)
      map({ "i", "n" }, "<C-r>", function()
        local it = state.get_selected_entry().value
        actions.close(bufnr)
        if it.mode == "n" then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(it.raw, true, false, true), "m", false)
        end
      end)
      return true
    end,
  }):find()
end

vim.keymap.set("n", "<leader>?", M.open, { desc = "Search keymaps (what key does…)" })

return M
