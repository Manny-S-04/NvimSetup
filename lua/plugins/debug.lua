-- Debugging UI. The .NET adapter/configurations are registered by easy-dotnet (dotnet.lua).
-- Visual Studio keys live in lua/vs-keymaps.lua.
return {
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "nvim-neotest/nvim-nio",
            "theHamsta/nvim-dap-virtual-text",
        },
        config = function()
            local dap, dapui = require("dap"), require("dapui")

            -- Visual Studio-ish layout: Locals/Watch/Call Stack/Breakpoints on the left,
            -- program output + Immediate window (REPL) along the bottom.
            dapui.setup({
                layouts = {
                    {
                        position = "left",
                        size = 45,
                        elements = {
                            { id = "scopes", size = 0.40 },
                            { id = "watches", size = 0.20 },
                            { id = "stacks", size = 0.25 },
                            { id = "breakpoints", size = 0.15 },
                        },
                    },
                    {
                        position = "bottom",
                        size = 12,
                        elements = {
                            { id = "console", size = 0.55 },
                            { id = "repl", size = 0.45 },
                        },
                    },
                },
            })
            require("nvim-dap-virtual-text").setup({}) -- variable values inline, like VS DataTips

            -- Breakpoint glyphs: red dot / condition / logpoint, current line highlighted.
            vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
            vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError" })
            vim.fn.sign_define("DapLogPoint", { text = "◉", texthl = "DiagnosticInfo" })
            vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DiagnosticWarn" })
            vim.fn.sign_define("DapStopped", { text = "➜", texthl = "DiagnosticWarn", linehl = "Visual" })

            dap.listeners.before.attach.dapui_config = function() dapui.open() end
            dap.listeners.before.launch.dapui_config = function() dapui.open() end
            dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
            dap.listeners.before.event_exited.dapui_config = function() dapui.close() end
        end,
    },
}
