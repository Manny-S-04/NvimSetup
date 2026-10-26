-- jira.nvim lives in this config repo (plugins-local/) so it syncs between machines.
-- Credentials come from JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN (never commit them here).
return {
    dir = vim.fn.stdpath("config") .. "/plugins-local/jira.nvim",
    name = "jira.nvim",
    cmd = { "Jira", "JiraMine", "JiraIssue", "JiraSearch", "JiraFind", "JiraBoard", "JiraRefresh",
        "JiraParent", "JiraChildren", "JiraWork", "JiraWorklist" },
    -- Worklist (a harpoon list of tickets, e.g. a parent's children): :JiraWork CV-123 fills it.
    keys = {
        { "<leader>jf", "<cmd>JiraFind<cr>", desc = "Jira: find tickets (query builder, no JQL)" },
        { "<leader>jw", "<cmd>JiraWorklist<cr>", desc = "Jira: worklist" },
        { "<leader>jn", "<cmd>JiraWorklist next<cr>", desc = "Jira: next worklist ticket" },
        { "<leader>jp", "<cmd>JiraWorklist prev<cr>", desc = "Jira: previous worklist ticket" },
        { "<leader>jW", "<cmd>JiraWork<cr>", desc = "Jira: worklist = parent's tickets (key under cursor)" },
    },
    opts = {
        board = 19, -- work's CV board: :JiraBoard with no argument opens it
    },
}
