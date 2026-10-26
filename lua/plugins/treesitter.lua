return {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            local config = require("nvim-treesitter.configs")
            config.setup({
                ensure_installed = {
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
                highlight = {
                    enable = true,
                    -- Off for >512 KB files and decompiled metadata (where F12 into a library lands).
                    disable = function(lang, buf) return require("crash-guard").ts_disable(lang, buf) end,
                },
                indent = { enable = true },
            })
            end
    }

