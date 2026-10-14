-- Visual Studio-style conveniences: Error List, Git gutter/diff, TODO list,
-- and a popup that shows what every <leader> key does.
return {
    -- Error List (and quickfix/build errors, references, TODOs) in a proper panel.
    {
        "folke/trouble.nvim",
        cmd = "Trouble",
        opts = {},
        keys = {
            { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Error List (all files)" },
            { "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Error List (this file)" },
            { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Build errors (quickfix)" },
            { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Document outline" },
        },
    },

    -- Changed-line markers in the gutter, hunk preview/stage/reset, inline blame.
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {
            on_attach = function(bufnr)
                local gs = require("gitsigns")
                local function map(lhs, rhs, desc)
                    vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
                end
                map("]h", function() gs.nav_hunk("next") end, "Next git change")
                map("[h", function() gs.nav_hunk("prev") end, "Previous git change")
                map("<leader>gp", gs.preview_hunk, "Preview change")
                map("<leader>gs", gs.stage_hunk, "Stage change")
                map("<leader>gR", gs.reset_hunk, "Undo change (reset hunk)")
                map("<leader>gb", function() gs.blame_line({ full = true }) end, "Blame line")
                map("<leader>gB", gs.toggle_current_line_blame, "Toggle inline blame")
            end,
        },
    },

    -- VS "Git Changes" / compare / merge-conflict view.
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
        keys = {
            { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Git changes (diff view)" },
            { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
            { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
        },
    },

    -- VS Task List: highlights TODO/FIXME/HACK and lists them.
    {
        "folke/todo-comments.nvim",
        event = { "BufReadPost", "BufNewFile" },
        dependencies = { "nvim-lua/plenary.nvim" },
        opts = { signs = false },
        keys = {
            { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
            { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous TODO" },
            { "<leader>xt", "<cmd>Trouble todo toggle<cr>", desc = "Task List (TODOs)" },
        },
    },
}
