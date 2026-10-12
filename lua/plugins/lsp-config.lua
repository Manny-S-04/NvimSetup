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
            require("mason").setup({
                PATH = "prepend",
                registries = {
                    "github:mason-org/mason-registry",
                    -- Provides the "roslyn" package (C# LSP, same version as VS Code) for roslyn.nvim
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
        config = function()
            --local capabilities = require("cmp_nvim_lsp").default_capabilities()
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities.textDocument.completion.completionItem.snippetSupport = true

            -- Native 0.11 API: "*" applies to every server; nvim-lspconfig supplies the
            -- per-server defaults (cmd, filetypes, root markers) via its lsp/*.lua files.
            vim.lsp.config("*", { capabilities = capabilities })
            vim.lsp.enable(lsps)

            vim.keymap.set("n", "<C-k>", vim.lsp.buf.hover, {})
            vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, {})
            --vim.keymap.set("n", "gr", vim.lsp.buf.references)
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
            --vim.keymap.set("n", "<leader>l", vim.diagnostic.setloclist, {})
        end,
    },
}
