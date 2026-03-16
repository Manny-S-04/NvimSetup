return {
    {
        "catppuccin/nvim",
        config = function()
        end,
    },
    {
        "folke/tokyonight.nvim",
        lazy = false,
        opts = {},
        config = function()
        end,
    },
    {
        "EdenEast/nightfox.nvim",
    },
    {
        "nyoom-engineering/oxocarbon.nvim",
    },
    {
        "zaldih/themery.nvim",
        lazy = false,
        config = function()
            require("themery").setup({
                themes = {
                    {name = "catppuccin", colorscheme = "catppuccin-mocha"},
                    {name = "tokyonight", colorscheme = "tokyonight-storm"},
                    {name = "nightfox-carbonfox", colorscheme = "carbonfox"},
                    {name = "nightfox-nordfox", colorscheme = "nordfox"},
                    {name = "oxocarbon", colorscheme = "oxocarbon"},
                },
                livePreview = true,
            })
        end
    }
}
