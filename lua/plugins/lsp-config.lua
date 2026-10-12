local lsps = {
    "gopls",
    "html",
    "cssls",
    "jsonls",
    "lua_ls",
    "ts_ls",
    "pyright",
    "rust_analyzer",
}

return {
    {
        "williamboman/mason.nvim",
        config = function()
            require("mason").setup({
                PATH = "prepend",
                registries = {
                    "github:mason-org/mason-registry",
                    "github:Crashdummyy/mason-registry",
                },
            })
        end,
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim" },
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = lsps,
                automatic_enable = false,
            })
        end,
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "seblyng/roslyn.nvim",
            "tris203/rzls.nvim",
        },
        config = function()
            --local capabilities = require("cmp_nvim_lsp").default_capabilities()
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities.textDocument.completion.completionItem.snippetSupport = true

            for _, lsp in ipairs(lsps) do
                require("lspconfig")[lsp].setup({
                    capabilities = capabilities,
                })
            end

            vim.lsp.config("rust_analyzer", {
                cmd = { "C:/Users/manny/appdata/local/nvim-data/mason/bin/rust-analyzer.cmd" },
                --cmd = { "/home/manny/.local/share/nvim/mason/bin/rust-analyzer" },
                capabilities = capabilities,
                filetypes = { "rust" },
            })
            require("rzls").setup({})
            require("roslyn").setup({
                capabilities = capabilities,
                config = {
                    settings = {
                        ["csharp|inlay_hints"] = {
                            csharp_enable_inlay_hints_for_implicit_object_creation = true,
                            csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                            dotnet_enable_inlay_hints_for_parameters = true,
                        },
                        ["csharp|code_lens"] = {
                            dotnet_enable_references_code_lens = true,
                        },
                    },
                },
                filewatching = "roslyn",
                broad_search = true,
            })
            vim.lsp.enable({ "roslyn", "rzls" })

            --vim.lsp.enable(lsps)
            vim.keymap.set("n", "<C-k>", vim.lsp.buf.hover, {})
            --vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, {})
            --vim.keymap.set("n", "gr", vim.lsp.buf.references)
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
            --vim.keymap.set("n", "<leader>l", vim.diagnostic.setloclist, {})
        end,
    },
}
