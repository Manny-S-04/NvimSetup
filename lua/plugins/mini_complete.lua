-- mini_complete lives in this config repo (plugins-local/) so it syncs between machines.
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/mini_complete.nvim",
    name = "mini_complete.nvim",
    event = "InsertEnter",
    opts = {
        notify_on_attach = true,
        keymaps = {
            snippet_next = "<C-l>",
            snippet_prev = "<C-h>",
        },
        -- Your previous fixed colours. Delete this table to follow the active colorscheme instead
        -- (the bar then links to Pmenu/PmenuSel and changes with Themery).
        highlights = {
            MiniCompleteNormal = { bg = "#1e1e2e", fg = "#cdd6f4" },
            MiniCompleteSelected = { bg = "#45475a", fg = "#f5e0dc", bold = true },
            MiniCompleteDocNormal = { bg = "#181825", fg = "#cdd6f4" },
            MiniCompleteDocBorder = { fg = "#585b70" },
            MiniCompleteSnippet = { fg = "#f38ba8" },
            MiniCompleteSnippetSelected = { bg = "#45475a", fg = "#f38ba8", bold = true },
        },
    },
}
