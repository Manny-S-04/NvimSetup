return {
    "sphamba/smear-cursor.nvim",
    opts = {
        stiffness = 0.5,
        trailing_stiffness = 0.49,
        never_draw_over_target = false,
        smear_between_buffers = true,
        smear_between_neighbor_lines = true,
        scroll_buffer_space = true,
        legacy_computing_symbols_support = false,
        smear_insert_mode = true,
        -- nvim-dap starts the debugged app in these buffers from inside a text-locked callback;
        -- drawing the smear there raises E565 and aborts the launch (F5 never attaches).
        filetypes_disabled = { "dapui_console", "dap-repl", "dap-terminal", "dapui_scopes",
            "dapui_watches", "dapui_stacks", "dapui_breakpoints" },
    },
}
