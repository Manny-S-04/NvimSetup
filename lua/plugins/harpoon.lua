return{
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-telescope/telescope.nvim" , "nvim-lua/plenary.nvim" },
    config = function ()
        local harpoon = require("harpoon")

        -- On Windows one file reaches harpoon spelled several ways (C:\Users\..\Documents\.. from :e,
        -- c:/users/../documents/.. from an LSP jump). Harpoon makes paths relative with a case-sensitive
        -- string compare against the cwd, so those were stored absolute and the menu showed the whole
        -- C:\Users\man20\Documents\Programming\ledger\ prefix. fs_realpath returns the on-disk
        -- spelling, so both sides compare equal and the path comes out relative to the project.
        ---@param path string
        ---@return string
        local function canonical(path)
            return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
        end

        ---@param path string absolute, or relative to the cwd
        ---@return string relative to the cwd when the file is inside it, else absolute
        local function relative(path)
            local abs = canonical(vim.fn.fnamemodify(path, ":p"))
            return vim.fs.relpath(canonical(vim.uv.cwd()), abs) or abs
        end

        harpoon:setup({
            -- Only the file list: the jira worklist list defines its own display/equals/create.
            default = {
                ---@param name string|nil set when a line is typed into the menu by hand
                create_list_item = function(_, name)
                    if name then return { value = relative(name), context = { row = 1, col = 0 } } end
                    local pos = vim.api.nvim_win_get_cursor(0)
                    return { value = relative(vim.api.nvim_buf_get_name(0)), context = { row = pos[1], col = pos[2] } }
                end,
                -- Entries saved before this fix are absolute; show them short too.
                display = function(item) return relative(item.value) end,
                -- ...and treat an old absolute entry and a new relative one as the same file (no duplicates).
                equals = function(a, b)
                    if a == nil or b == nil then return a == b end
                    return relative(a.value) == relative(b.value)
                end,
            },
        })
        vim.keymap.set("n", "<leader>ha", function () harpoon:list():add() end, { desc = "Harpoon: add file" })
        vim.keymap.set("n", "<leader>hm", function () harpoon.ui:toggle_quick_menu(harpoon:list())   end, { desc = "Harpoon: menu" })
        vim.keymap.set("n", "<leader>1", function () harpoon:list():select(1) end, { desc = "Harpoon: file 1" })
        vim.keymap.set("n", "<leader>2", function () harpoon:list():select(2) end, { desc = "Harpoon: file 2" })
        vim.keymap.set("n", "<leader>3", function () harpoon:list():select(3) end, { desc = "Harpoon: file 3" })
        vim.keymap.set("n", "<leader>4", function () harpoon:list():select(4) end, { desc = "Harpoon: file 4" })
        vim.keymap.set("n", "<leader>5", function () harpoon:list():select(5) end, { desc = "Harpoon: file 5" })
        vim.keymap.set("n", "<leader>6", function () harpoon:list():select(6) end, { desc = "Harpoon: file 6" })
        vim.keymap.set("n", "<leader>7", function () harpoon:list():select(7) end, { desc = "Harpoon: file 7" })
        vim.keymap.set("n", "<leader>8", function () harpoon:list():select(8) end, { desc = "Harpoon: file 8" })
        vim.keymap.set("n", "<leader>9", function () harpoon:list():select(9) end, { desc = "Harpoon: file 9" })
        vim.keymap.set("n", "<leader>0", function () harpoon:list():select(0) end, { desc = "Harpoon: file 0" })

        local conf = require("telescope.config").values
        local function toggle_telescope(harpoon_files)
            local file_paths = {}
            for _, item in ipairs(harpoon_files.items) do
                table.insert(file_paths, relative(item.value)) -- short here too; relative paths open against the cwd
            end

            require("telescope.pickers").new({}, {
                prompt_title = "Harpoon",
                finder = require("telescope.finders").new_table({
                    results = file_paths,
                }),
                previewer = conf.file_previewer({}),
                sorter = conf.generic_sorter({}),
            }):find()
    end
    vim.keymap.set("n", "<C-h>", function() toggle_telescope(harpoon:list()) end,
        { desc = "Open harpoon window" })
    end,
}
