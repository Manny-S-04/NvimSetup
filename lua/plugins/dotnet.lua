-- .NET tooling: build/run/test/debug with launch profiles, NuGet, user secrets, EF Core,
-- `dotnet new` templates, solution-wide diagnostics, and the Roslyn language server.
-- Needs the EasyDotnet dotnet tool:  dotnet tool install -g EasyDotnet
return {
    "GustavEikaas/easy-dotnet.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim", "mfussenegger/nvim-dap" },
    ft = { "cs", "csproj", "sln", "slnx", "razor", "fsproj", "xml" },
    cmd = "Dotnet",
    config = function()
        require("easy-dotnet").setup({
            picker = "telescope",
            lsp = {
                -- Roslyn. vim.g.csharp_lsp = "roslyn.nvim" (in init.lua) skips it and uses your previous
                -- roslyn.nvim setup instead; by default lua/csharp-lsp.lua falls back to it automatically.
                enabled = vim.g.csharp_lsp ~= "roslyn.nvim",
                roslynator_enabled = true,
                auto_refresh_codelens = true, -- "3 references" above members, like VS CodeLens
                config = {
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
                            dotnet_enable_tests_code_lens = true,
                        },
                        ["csharp|background_analysis"] = {
                            dotnet_analyzer_diagnostics_scope = "openFiles",
                            dotnet_compiler_diagnostics_scope = "openFiles",
                        },
                    },
                },
            },
            debugger = {
                engine = "netcoredbg",
                console = "integratedTerminal",
            },
            test_runner = {
                viewmode = "vsplit",
                vsplit_pos = "botright", -- right-hand side, like VS's Test Explorer
                -- In .cs test files. The defaults (<leader>r/t/d/p) would clash with your
                -- resize mode and neotest keys, so they live under <leader>n like the rest.
                mappings = {
                    run_test_from_buffer = { lhs = "<leader>nu", desc = "run test under cursor" },
                    run_all_tests_from_buffer = { lhs = "<leader>nU", desc = "run all tests in file" },
                    debug_test_from_buffer = { lhs = "<leader>nD", desc = "debug test under cursor" },
                    peek_stack_trace_from_buffer = { lhs = "<leader>nk", desc = "peek failed test stack trace" },
                },
            },
            auto_bootstrap_namespace = {
                type = "file_scoped",    -- new .cs files start with `namespace X;` + a class
                enabled = true,
            },
            diagnostics = {
                default_severity = "warning",
                setqflist = false,
            },
        })

        -- C# inlay hints (parameter names, implicit types), as before.
        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("DotnetInlayHints", { clear = true }),
            callback = function(args)
                local client = vim.lsp.get_client_by_id(args.data.client_id)
                -- easy-dotnet's Roslyn client is called "easy_dotnet"
                if client and (client.name == "easy_dotnet" or client.name == "roslyn") then
                    vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
                end
            end,
        })
    end,
}
