return {
    "ej-shafran/compile-mode.nvim",
    version = "^5.0.0",
    branch = "latest",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "m00qek/baleia.nvim",
    },
    config = function()
        ---@type CompileModeOpts
        vim.g.compile_mode = {
            baleia_setup = true,
            bang_expansion = true,
            default_command = "",
            -- To use different defaults based on filetype, you can use a table:
            -- default_command = {
            --   javascript = "npm %",
            --   typescript = "npm %",
            --   c = "cc -o %:r % && ./%:r",
            --   go = "go %",
            --   rust = "cargo %"
            -- },
            auto_scroll = true,
            -- Jump back past the end/beginning of the errors
            -- with `:NextError`/`:PrevError`
            focus_compilation_buffer = true,
        }
    end
}
