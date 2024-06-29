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
                        "c_sharp",
                        "css",
                        "elixir",
                        "go",
                        "html",
                        "javascript",
                        "lua",
                        "python",
                        "rust",
                        "typescript",
                        "vue",
                        "xml",
                },
                auto_install = true,
                highlight = { enable = true },
                indent = { enable = true },
                autotag = {
                    enable = true,
                },
            })
            end
    }

