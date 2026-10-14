return{
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-telescope/telescope.nvim" , "nvim-lua/plenary.nvim" },
    config = function ()
        local harpoon = require("harpoon")
        harpoon:setup()
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
                table.insert(file_paths, item.value)
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
