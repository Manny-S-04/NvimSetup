-- sprints.nvim (Zoho Sprints) lives in this config repo (plugins-local/) so it syncs between machines.
-- Credentials come from ZOHO_DC / ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / ZOHO_REFRESH_TOKEN
-- (+ ZOHO_SPRINTS_TEAM / ZOHO_SPRINTS_PROJECT / ZOHO_SPRINTS_USER) — never commit them here.
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/sprints.nvim",
    name = "sprints.nvim",
    cmd = { "Sprints", "SprintsMine", "SprintsSprint", "SprintsBacklog", "SprintsItem",
        "SprintsProject", "SprintsRefresh", "SprintsRaw", "SprintsBoard", "SprintsNew", "SprintsSearch",
        "SprintsFind", "SprintsParent", "SprintsChildren", "SprintsWork", "SprintsWorklist" },
    -- Item buffers are named sprints://I22516: load on reading one (harpoon, :e, a session),
    -- so a ticket reopens by name before any :Sprints command has run.
    event = { "BufReadCmd sprints:/*" }, -- matches sprints://I1 and harpoon's sprints:/I1
    -- Worklist (a harpoon list of items, e.g. a parent's sub items): :SprintsWork I123 fills it.
    -- <leader>s = Sprints (<leader>j stays jira.nvim's)
    keys = {
        { "<leader>sm", "<cmd>SprintsMine<cr>", desc = "Sprints: my items in the active sprint" },
        { "<leader>sb", "<cmd>SprintsBoard<cr>", desc = "Sprints: board (active sprint by status)" },
        { "<leader>sl", "<cmd>SprintsBacklog<cr>", desc = "Sprints: backlog" },
        { "<leader>sn", "<cmd>SprintsNew<cr>", desc = "Sprints: new item" },
        { "<leader>si", "<cmd>SprintsItem<cr>", desc = "Sprints: open the item under the cursor" },
        { "<leader>ss", ":SprintsSearch ", desc = "Sprints: search (title or number)" },
        { "<leader>sf", "<cmd>SprintsFind<cr>", desc = "Sprints: find items (query builder)" },
        { "<leader>sw", "<cmd>SprintsWorklist<cr>", desc = "Sprints: worklist" },
        { "<leader>sj", "<cmd>SprintsWorklist next<cr>", desc = "Sprints: next worklist item" },
        { "<leader>sk", "<cmd>SprintsWorklist prev<cr>", desc = "Sprints: previous worklist item" },
        { "<leader>sW", "<cmd>SprintsWork<cr>", desc = "Sprints: worklist = parent's items (item under cursor)" },
    },
    opts = {},
}
