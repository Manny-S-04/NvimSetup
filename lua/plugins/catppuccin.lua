return {
    "catppuccin/nvim",
    flavor = "mocha",
    name = "catppuccin",
    priority = 1000,
    config = function()
        vim.cmd("colorscheme catppuccin")
    end,
}
