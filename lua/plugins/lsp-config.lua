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
                automatic_enable = true,
            })
        end,
    },
    {
        "neovim/nvim-lspconfig",
        config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()
            for _, lsp in ipairs(lsps) do
                vim.lsp.config(lsp, { capabilities = capabilities })
            end
            --vim.lsp.config("rust_analyzer", {
              --  cmd = { "C:/Users/man20/appdata/local/nvim-data/mason/bin/rust-analyzer.cmd" },
               -- capabilities = capabilities,
            --})
            vim.lsp.enable(lsps)
            vim.keymap.set("n", "<C-I>", vim.lsp.buf.hover, {})
            --vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, {})
            --vim.keymap.set("n", "gr", vim.lsp.buf.references)
            vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
            --vim.keymap.set("n", "<leader>l", vim.diagnostic.setloclist, {})
        end,
    },
}
