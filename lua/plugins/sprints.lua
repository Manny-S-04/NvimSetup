-- sprints.nvim (Zoho Sprints) lives in this config repo (plugins-local/) so it syncs between machines.
-- Credentials come from ZOHO_DC / ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / ZOHO_REFRESH_TOKEN
-- (+ ZOHO_SPRINTS_TEAM / ZOHO_SPRINTS_PROJECT / ZOHO_SPRINTS_USER) — never commit them here.
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/sprints.nvim",
    name = "sprints.nvim",
    cmd = { "Sprints", "SprintsMine", "SprintsSprint", "SprintsBacklog", "SprintsItem",
        "SprintsProject", "SprintsRefresh", "SprintsRaw" },
    opts = {},
}
