return {
    {
        "nvim-telescope/telescope-ui-select.nvim",
    },
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.6",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            vim.api.nvim_create_autocmd("User", {
                pattern = "TelescopePreviewerLoaded",
                callback = function(args)
                    vim.wo.wrap = true
                    vim.wo.linebreak = true
                end,
            })
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
            vim.keymap.set("n", "<leader>fs", builtin.live_grep, {})
            vim.keymap.set("v", "<leader>fs", builtin.grep_string, {})
            vim.keymap.set("n", "<leader>ds", builtin.lsp_document_symbols, {})
            vim.keymap.set({"n", "v"}, "<leader>gr", builtin.lsp_references, {})
            vim.keymap.set("n", "<A-F2>", builtin.lsp_implementations, {})
            vim.keymap.set("n", "<F12>", builtin.lsp_definitions, {})
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
            local width = 0.6

            require("telescope").setup({
                defaults = {
                    path_display = { "filename_first" },
                },
                pickers = {
                    live_grep = {
                        layout_strategy = "horizontal",
                        layout_config = {
                            horizontal = {
                                preview_width = width,
                            },
                        },
                    },
                    lsp_references = {
                        layout_strategy = "horizontal",
                        layout_config = {
                            horizontal = {
                                preview_width = width,
                            },
                        },
                    },
                },
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
