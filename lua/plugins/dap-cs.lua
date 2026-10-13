return {
    {
        "theHamsta/nvim-dap-virtual-text",
        dependencies = { "mfussenegger/nvim-dap" },
        opts = {},
    },
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "nvim-neotest/nvim-nio",
            "williamboman/mason.nvim",
            "jay-babu/mason-nvim-dap.nvim",
        },
        config = function()
            local dap = require("dap")
            local dapui = require("dapui")

            require("mason-nvim-dap").setup({
                ensure_installed = { "netcoredbg" },
                automatic_installation = true,
            })

            dap.adapters.coreclr = {
                type = "executable",
                -- On Windows Mason installs a netcoredbg.cmd shim; exepath() resolves the
                -- extension (Mason's bin dir is on PATH), a bare path without .cmd fails to spawn.
                command = vim.fn.exepath("netcoredbg") ~= "" and vim.fn.exepath("netcoredbg")
                    or (vim.fn.stdpath("data") .. "/mason/bin/netcoredbg"),
                args = { "--interpreter=vscode" },
            }

            dap.configurations.cs = {
                {
                    type = "coreclr",
                    name = "launch - netcoredbg",
                    request = "launch",
                    program = function()
                        return vim.fn.input(
                            "Path to dll: ",
                            vim.fn.getcwd() .. "/bin/Debug/net8.0/",
                            "file"
                        )
                    end,
                },
            }

            dapui.setup()
            dap.listeners.before.attach.dapui_config = function() dapui.open() end
            dap.listeners.before.launch.dapui_config = function() dapui.open() end
            dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
            dap.listeners.before.event_exited.dapui_config = function() dapui.close() end

            vim.keymap.set("n", "<F5>", dap.continue)
            vim.keymap.set("n", "<F10>", dap.step_over)
            vim.keymap.set("n", "<F11>", dap.step_into)
            vim.keymap.set("n", "<S-F11>", dap.step_out) -- Visual Studio's binding; <F12> is go-to-definition
            vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint)
        end,
    },
}
