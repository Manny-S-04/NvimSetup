return {
    "nvim-lualine/lualine.nvim",
    config = function()
        require('lualine').setup({
            options = {
                theme = 'dracula'
                },
            sections = {
                -- While a debug session exists: the keys you need right now (lua/guide). Hidden otherwise.
                lualine_x = {
                    {
                        function() return require("guide").statusline() end,
                        cond = function() return package.loaded["guide"] and require("guide").statusline_active() end,
                        color = "WarningMsg",
                    },
                    "encoding", "fileformat", "filetype",
                },
            },
        })
    end
}
