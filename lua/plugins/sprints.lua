-- sprints.nvim (Zoho Sprints) lives in this config repo (plugins-local/) so it syncs between machines.
-- Credentials come from ZOHO_DC / ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / ZOHO_REFRESH_TOKEN
-- (+ ZOHO_SPRINTS_TEAM / ZOHO_SPRINTS_PROJECT / ZOHO_SPRINTS_USER) — never commit them here.
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/sprints.nvim",
    name = "sprints.nvim",
    cmd = { "Sprints", "SprintsMine", "SprintsSprint", "SprintsBacklog", "SprintsItem",
        "SprintsProject", "SprintsRefresh", "SprintsRaw", "SprintsBoard", "SprintsNew", "SprintsSearch" },
    -- <leader>s = Sprints (<leader>j stays jira.nvim's)
    keys = {
        { "<leader>sm", "<cmd>SprintsMine<cr>", desc = "Sprints: my items in the active sprint" },
        { "<leader>sb", "<cmd>SprintsBoard<cr>", desc = "Sprints: board (active sprint by status)" },
        { "<leader>sl", "<cmd>SprintsBacklog<cr>", desc = "Sprints: backlog" },
        { "<leader>sn", "<cmd>SprintsNew<cr>", desc = "Sprints: new item" },
        { "<leader>si", "<cmd>SprintsItem<cr>", desc = "Sprints: open the item under the cursor" },
        { "<leader>ss", ":SprintsSearch ", desc = "Sprints: search titles" },
    },
    opts = {},
}
