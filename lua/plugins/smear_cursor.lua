return {
  "sphamba/smear-cursor.nvim",
    config = function ()
        require("smear_cursor").setup({
        opts = {
            stiffness = 0.5,
            trailing_stiffness = 0.49,
            never_draw_over_target = false,
            smear_between_buffers = true,
            smear_between_neighbor_lines = true,
            scroll_buffer_space = true,
            legacy_computing_symbols_support = false,
            smear_insert_mode = true,
          },
        })
    end
}
