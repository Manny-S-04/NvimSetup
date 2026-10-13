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
                    -- The main registry must stay first: lua_ls, gopls, netcoredbg etc. live there.
                    "github:mason-org/mason-registry",
                    -- Adds the "roslyn" package (C# LSP, same version as VS Code) used by roslyn.lua
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
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities.textDocument.completion.completionItem.snippetSupport = true

            -- Native 0.11 API: "*" applies to every server; nvim-lspconfig supplies the
            -- per-server defaults (cmd, filetypes, root markers) via its lsp/*.lua files.
            -- C#/Razor is configured separately in roslyn.lua.
            vim.lsp.config("*", { capabilities = capabilities })
            vim.lsp.enable(lsps)

            vim.keymap.set("n", "<C-k>", vim.lsp.buf.hover, { desc = "LSP hover" })
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })
            -- <F12> (go to definition) is mapped in telescope.lua.
        end,
    },
}
