return {
    {
        "williamboman/mason.nvim",
        config = function()
            require("mason").setup({ PATH = "prepend",
            })
        end,
    },
    {
        "williamboman/mason-lspconfig.nvim",
        config = function()
            require("mason-lspconfig").setup({
                ensure_installed = {
                    "gopls",
                    "html",
                    "cssls",
                    "jsonls",
                    "lua_ls",
                    "ts_ls",
                    "pyright",
                    "rust_analyzer",
                },
                automatic_installation = true,
            })
        end,
    },
    {
        "neovim/nvim-lspconfig",
        config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()
            local lspconfig = require("lspconfig")
            lspconfig.lua_ls.setup({ capabilities = capabilities })
            lspconfig.ts_ls.setup({ capabilities = capabilities })
            lspconfig.cssls.setup({ capabilities = capabilities })
            lspconfig.gopls.setup({ capabilities = capabilities })
            lspconfig.html.setup({ capabilities = capabilities })
            lspconfig.jsonls.setup({ capabilities = capabilities })
            lspconfig.pyright.setup({ capabilities = capabilities })
            lspconfig.rust_analyzer.setup({
                capabilities = capabilities,
                cmd = { "C:/Users/man20/appdata/local/nvim-data/mason/bin/rust-analyzer.cmd" },
            })
            vim.keymap.set("n", "<C-I>", vim.lsp.buf.hover, {})
            vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, {})
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
        end,
    },
}
