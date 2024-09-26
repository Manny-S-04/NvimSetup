return 
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            local config = require("nvim-treesitter.configs")
            config.setup({
                ensure_installed = 
                    {
                        "cpp",
                        "bash",
                        "css",
                        "go",
                        "html",
                        "javascript",
                        "lua",
                        "python",
                        "typescript",
                        "xml",
                },
                auto_install = true,
                highlight = { enable = true },
                indent = { enable = true },
            })
            end
    }

