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

            -- Panels follow what you're doing, not whether a session exists:
            --   paused (breakpoint / step)  -> panels open
            --   running (F5 continue)       -> panels close, you get your code back
            -- Stepping (F10/F11) sends "continued" then "stopped" a few ms apart, so the close
            -- is delayed and cancelled if we stop again: no flicker while stepping.
            -- Space du still shows/hides them by hand (e.g. to read program output while running).
            local HIDE_DELAY_MS = 400
            local hide_timer = nil ---@type uv.uv_timer_t|nil

            local function cancel_hide()
                if hide_timer then
                    hide_timer:stop()
                    hide_timer:close()
                    hide_timer = nil
                end
            end

            local function show()
                cancel_hide()
                require("zoom").unzoom() -- a breakpoint hit wins over zoom: you want to see locals
                dapui.open()
            end

            local function hide_soon()
                cancel_hide()
                hide_timer = vim.defer_fn(function()
                    hide_timer = nil
                    local s = dap.session()
                    if not (s and s.stopped_thread_id) then dapui.close() end
                end, HIDE_DELAY_MS)
            end

            local function hide_now()
                cancel_hide()
                dapui.close()
            end

            dap.listeners.after.event_stopped.dapui_config = show
            dap.listeners.after.event_continued.dapui_config = hide_soon
            dap.listeners.before.event_terminated.dapui_config = hide_now
            dap.listeners.before.event_exited.dapui_config = hide_now
        end,
    },
}
