-- C# / Razor via Microsoft's Roslyn language server (the same server the VS Code C# extension uses).
-- Requirements: Neovim >= 0.11 and the .NET SDK on PATH (`dotnet --version` must work).
-- The server binary is installed automatically through Mason (package "roslyn", from the
-- Crashdummyy registry added in lsp-config.lua — it tracks the version VS Code ships).
return {
    "seblyng/roslyn.nvim",
    -- Fallback only: easy-dotnet.nvim (dotnet.lua) normally runs Roslyn. lua/csharp-lsp.lua loads this
    -- plugin (which starts its own Roslyn) only if easy-dotnet's server doesn't attach or dies.
    lazy = true,
    -- Pinned: the next commit (dbd677f, "feat!: >=0.12") drops Neovim 0.11 support.
    -- Remove this pin once you move to Neovim 0.12.
    commit = "f2ec6ee6384c3b611ddc817b9e78b20cd0334bbb",
    dependencies = { "williamboman/mason.nvim" },
    ---@module 'roslyn.config'
    ---@type RoslynNvimConfig
    opts = {
        -- Roslyn does its own file watching; Neovim's watcher is slow on big solutions (esp. Windows).
        filewatching = "roslyn",
        -- Search child dirs for .sln/.slnx too, for repos where projects aren't under the solution dir.
        broad_search = true,
    },
    config = function(_, opts)
        -- Neovim has no built-in "razor" filetype; roslyn.nvim attaches to it (Razor cohosting).
        vim.filetype.add({ extension = { razor = "razor", cshtml = "razor" } })

        vim.lsp.config("roslyn", {
            settings = {
                ["csharp|inlay_hints"] = {
                    csharp_enable_inlay_hints_for_implicit_object_creation = true,
                    csharp_enable_inlay_hints_for_implicit_variable_types = true,
                    csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                    csharp_enable_inlay_hints_for_types = true,
                    dotnet_enable_inlay_hints_for_parameters = true,
                },
                ["csharp|code_lens"] = {
                    dotnet_enable_references_code_lens = true,
                },
                ["csharp|background_analysis"] = {
                    -- "openFiles" keeps big solutions responsive; switch to "fullSolution" for project-wide diagnostics.
                    dotnet_analyzer_diagnostics_scope = "openFiles",
                    dotnet_compiler_diagnostics_scope = "openFiles",
                },
            },
        })

        require("roslyn").setup(opts)

        -- Turn inlay hints on for C# buffers only (your other servers keep their current behaviour).
        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("RoslynAttach", { clear = true }),
            callback = function(args)
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                if client and client.name == "roslyn" then
                    vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
                end
            end,
        })

        -- Install the server on first run so a fresh machine works without :MasonInstall.
        local registry = require("mason-registry")
        registry.refresh(function()
            local ok, pkg = pcall(registry.get_package, "roslyn")
            if ok and not pkg:is_installed() then
                vim.notify("Installing roslyn language server via Mason…")
                pkg:install()
            end
        end)
    end,
}
