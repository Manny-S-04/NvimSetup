return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.6",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
            vim.keymap.set("n", "<leader>fs", builtin.live_grep, {})
            vim.keymap.set("v", "<leader>fs", builtin.grep_string, {})
            vim.keymap.set("n", "<leader>ds", builtin.lsp_document_symbols, {})
            vim.keymap.set("n", "<leader>gr", builtin.lsp_references, {})
            vim.keymap.set("n", "<A-F2>", builtin.lsp_implementations, {})
            vim.keymap.set("n", "<A-F12>", builtin.lsp_definitions, {})
            vim.keymap.set("n", "<leader>le",
                function ()
                    builtin.diagnostics({
                        bufnr = 0,
                        severity = vim.diagnostic.severity.ERROR,
                        previewer = true,
                        layout_strategy = "vertical"
                    })
                end
                , {})
        end,
    },
    {
        "nvim-telescope/telescope-ui-select.nvim",
        config = function()
            require("telescope").setup({
                extensions = {
                    ["ui-select"] = {
                        require("telescope.themes").get_dropdown({}),
                    },
                },
            })
            require("telescope").load_extension("ui-select")
        end,
    },
}
