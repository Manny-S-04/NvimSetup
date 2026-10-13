-- jira.nvim lives in this config repo (plugins-local/) so it syncs between machines.
-- Credentials come from JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN (never commit them here).
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/jira.nvim",
    name = "jira.nvim",
    cmd = { "Jira", "JiraMine", "JiraIssue", "JiraSearch", "JiraRefresh" },
    opts = {},
}
