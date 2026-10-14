-- Visual Studio muscle memory for .NET work.
-- Function keys work in every terminal. Combos like Ctrl+. and Ctrl+Shift+B only reach Neovim if
-- your terminal sends them (Windows Terminal usually does), so each has a <leader> fallback.
-- Forgot a key? <leader>? searches every mapping by description.
local map = vim.keymap.set

local function dap() return require("dap") end
-- easy-dotnet's features are subcommands of :Dotnet (lazy.nvim loads the plugin on first use).
local function dotnet(args) return function() vim.cmd("Dotnet " .. args) end end
-- Is there a .sln/.slnx/.csproj/.fsproj above the current file (or cwd)?
local function in_dotnet_project()
    local start = vim.fn.expand("%:p:h")
    if start == "" then start = vim.fn.getcwd() end
    return #vim.fs.find(function(name)
        return name:match("%.slnx?$") or name:match("%.[cf]sproj$")
    end, { upward = true, path = start, limit = 1 }) > 0
end

-- ── Debugging ──────────────────────────────────────────────────────────────────────────
-- F5: continue if debugging; otherwise start the default project with its launch profile
-- (launchSettings.json). Asks for project + profile once and remembers them, like VS's
-- startup project; <leader>nd picks again, <leader>nz forgets the remembered choice.
map("n", "<F5>", function()
    if dap().session() then
        dap().continue()
    elseif in_dotnet_project() then
        vim.cmd("Dotnet debug profile default")
    else
        dap().continue()
    end
end, { desc = "Debug: start / continue (F5)" })
map("n", "<S-F5>", function()
    dap().terminate()
end, { desc = "Debug: stop (Shift+F5)" })
map("n", "<C-S-F5>", function() dap().restart() end, { desc = "Debug: restart (Ctrl+Shift+F5)" })
map("n", "<C-F5>", dotnet("run profile default"), { desc = "Run without debugging (Ctrl+F5)" })

map("n", "<F9>", function() dap().toggle_breakpoint() end, { desc = "Debug: toggle breakpoint (F9)" })
map("n", "<C-S-F9>", function() dap().clear_breakpoints() end, { desc = "Debug: delete all breakpoints" })
map("n", "<F10>", function() dap().step_over() end, { desc = "Debug: step over (F10)" })
map("n", "<F11>", function() dap().step_into() end, { desc = "Debug: step into (F11)" })
map("n", "<S-F11>", function() dap().step_out() end, { desc = "Debug: step out (Shift+F11)" })
map("n", "<C-F10>", function() dap().run_to_cursor() end, { desc = "Debug: run to cursor (Ctrl+F10)" })
map({ "n", "v" }, "<S-F9>", function() require("dapui").eval() end, { desc = "Debug: QuickWatch (Shift+F9)" })

map("n", "<leader>b", function() dap().toggle_breakpoint() end, { desc = "Debug: toggle breakpoint" })
map("n", "<leader>dc", function()
    dap().set_breakpoint(vim.fn.input("Condition: "))
end, { desc = "Debug: conditional breakpoint" })
map("n", "<leader>dh", function()
    dap().set_breakpoint(nil, vim.fn.input("Hit count: "))
end, { desc = "Debug: hit-count breakpoint" })
map("n", "<leader>dl", function()
    dap().set_breakpoint(nil, nil, vim.fn.input("Log message ({expr} interpolates): "))
end, { desc = "Debug: tracepoint (log, don't stop)" })
map("n", "<leader>da", dotnet("debug attach"), { desc = "Debug: attach to process" })
map("n", "<leader>dr", function() dap().repl.toggle() end, { desc = "Debug: Immediate window (REPL)" })
map("n", "<leader>du", function() require("dapui").toggle() end, { desc = "Debug: toggle windows" })
map("n", "<leader>dk", function() dap().up() end, { desc = "Debug: up the call stack" })
map("n", "<leader>dj", function() dap().down() end, { desc = "Debug: down the call stack" })

-- ── Build / run / test (.NET) ─────────────────────────────────────────────────────────
map("n", "<C-S-b>", dotnet("build solution quickfix"), { desc = "Build solution (Ctrl+Shift+B)" })
map("n", "<leader>nb", dotnet("build solution quickfix"), { desc = "Build solution" })
map("n", "<leader>nB", dotnet("build quickfix"), { desc = "Build project…" })
map("n", "<leader>nc", dotnet("clean"), { desc = "Clean" })
map("n", "<leader>nx", dotnet("restore"), { desc = "Restore packages" })
map("n", "<leader>nr", dotnet("run profile default"), { desc = "Run default project" })
map("n", "<leader>nz", dotnet("reset"), { desc = "Forget remembered project/profile" })
map("n", "<leader>nR", dotnet("run profile"), { desc = "Run project + launch profile…" })
map("n", "<leader>nd", dotnet("debug profile"), { desc = "Debug project + launch profile…" })
map("n", "<leader>nw", dotnet("watch default"), { desc = "dotnet watch (hot reload)" })
map("n", "<leader>ns", function() require("easy-dotnet").stop() end, { desc = "Stop running projects" })
map("n", "<leader>nq", dotnet("terminal toggle"), { desc = "Toggle build/run output" })
map("n", "<leader>nt", dotnet("testrunner"), { desc = "Test Explorer" })
map("n", "<leader>nT", dotnet("test solution"), { desc = "Run all tests (solution)" })
map("n", "<leader>np", dotnet("add package"), { desc = "NuGet: add package" })
map("n", "<leader>nP", dotnet("remove package"), { desc = "NuGet: remove package" })
map("n", "<leader>no", dotnet("outdated"), { desc = "NuGet: outdated packages" })
map("n", "<leader>nS", dotnet("secrets"), { desc = "User secrets" })
map("n", "<leader>nn", dotnet("createfile"), { desc = "Add new item (template)…" })
map("n", "<leader>nN", dotnet("new"), { desc = "New project (template)…" })
map("n", "<leader>ne", dotnet("diagnostic"), { desc = "Solution-wide errors & warnings" })
map("n", "<leader>nma", dotnet("ef migrations add"), { desc = "EF: add migration" })
map("n", "<leader>nmr", dotnet("ef migrations remove"), { desc = "EF: remove last migration" })
map("n", "<leader>nmu", dotnet("ef database update"), { desc = "EF: update database" })
map("n", "<leader>nml", dotnet("ef migrations list"), { desc = "EF: list migrations" })

-- ── Code navigation / editing ─────────────────────────────────────────────────────────
-- F12 (definition) and F2 (rename) are already mapped in telescope.lua / vim-options.lua.
map("n", "<S-F12>", function() require("telescope.builtin").lsp_references() end, { desc = "Find all references (Shift+F12)" })
map("n", "<C-F12>", function() require("telescope.builtin").lsp_implementations() end, { desc = "Go to implementation (Ctrl+F12)" })
map("n", "<A-F12>", function()
    -- Peek definition: open it in a floating preview without leaving the current buffer.
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    vim.lsp.buf_request(0, "textDocument/definition", params, function(_, result)
        if result and not vim.tbl_isempty(result) then
            vim.lsp.util.preview_location(result[1] or result, { border = "rounded", max_height = 20 })
        end
    end)
end, { desc = "Peek definition (Alt+F12)" })
map({ "n", "v" }, "<C-.>", vim.lsp.buf.code_action, { desc = "Quick actions (Ctrl+.)" })
map("n", "<leader>cf", function() vim.lsp.buf.format({ async = true }) end, { desc = "Format document" })
map("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "Call hierarchy: callers" })
map("n", "<leader>co", vim.lsp.buf.outgoing_calls, { desc = "Call hierarchy: callees" })
map("n", "<leader>cl", vim.lsp.codelens.run, { desc = "Run CodeLens on this line" })
