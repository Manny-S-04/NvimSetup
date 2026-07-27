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

local server_filetypes = {
    gopls          = { "go" },
    html           = { "html" },
    cssls          = { "css", "scss", "less" },
    jsonls         = { "json" },
    lua_ls         = { "lua" },
    ts_ls          = { "typescript", "javascript", "typescriptreact", "javascriptreact" },
    pyright        = { "python" },
    rust_analyzer  = { "rust" },
}

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
                --cmd = { "C:/Users/man20/appdata/local/nvim-data/mason/bin/rust-analyzer.cmd" },
                cmd = { "/home/manny/.local/share/nvim/mason/bin/rust-analyzer" },
                capabilities = capabilities,
                filetypes = { "rust" },
            })
            --vim.lsp.enable(lsps)
            vim.keymap.set("n", "<C-k>", vim.lsp.buf.hover, {})
            --vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, {})
            --vim.keymap.set("n", "gr", vim.lsp.buf.references)
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
            --vim.keymap.set("n", "<leader>l", vim.diagnostic.setloclist, {})
        end,
    },
}
