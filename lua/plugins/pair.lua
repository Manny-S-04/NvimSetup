-- pair: load it from your local clone (for working on it) or from GitHub (like anyone else would).
--
-- Pick the source with PAIR_SOURCE=local|github (environment variable), or :lua vim.g.pair_source = "github"
-- before lazy loads. Default: your clone if it exists on this machine, otherwise GitHub.
local local_dir = vim.fn.expand("~/AI/pair") -- C:\Users\<you>\AI\pair on Windows, ~/AI/pair on Linux
local github_repo = nil -- set to "<your-github-user>/pair" once it's pushed

local source = vim.env.PAIR_SOURCE or vim.g.pair_source
    or (vim.fn.isdirectory(local_dir) == 1 and "local" or "github")

local spec = {
    name = "pair",
    lazy = false,
    opts = {
        complete = { accept = "<C-y>", accept_line = "<M-y>" },
        -- provider = { "work", "home" },  -- LLM servers from ~/.pair/config.json (see pair's README)
    },
    keys = {
        { "<leader>pa", ":PairAsk<CR>", mode = { "n", "v" }, desc = "pair: ask" },
        { "<leader>pj", "<cmd>PairJobs<CR>", desc = "pair: jobs" },
        { "<leader>pl", "<cmd>PairLast<CR>", desc = "pair: last result" },
        { "<leader>pp", "<cmd>PairProvider<CR>", desc = "pair: LLM for jobs" },
        { "<leader>pP", "<cmd>PairProvider!<CR>", desc = "pair: LLM for ghost text" },
        { "<leader>pt", "<cmd>PairTeach<CR>", desc = "pair: teach it a rule (stop repeating a mistake)" },
    },
}

if source == "local" then
    spec.dir = local_dir
    spec.cond = vim.fn.isdirectory(local_dir) == 1 -- skip quietly on machines without the clone
elseif github_repo then
    spec[1] = github_repo
else
    spec.dir = local_dir
    spec.cond = false -- GitHub chosen but github_repo isn't set yet
end

return spec
