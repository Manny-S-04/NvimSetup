local util = require("sprints.ui.util")

describe("wrap", function()
  before_each(function()
    vim.o.wrap = false -- like a global `nowrap` config
    require("sprints").setup({})
  end)

  it("wraps item buffers window-locally, at word boundaries", function()
    local bufnr = util.named_scratch("sprints://I-wrap-test", "sprints-item")
    vim.api.nvim_set_current_buf(bufnr)
    assert.is_true(vim.wo.wrap)
    assert.is_true(vim.wo.linebreak)
    assert.is_true(vim.wo.breakindent)
    assert.is_false(vim.go.wrap)

    vim.cmd("enew")
    assert.is_false(vim.wo.wrap) -- the next buffer in this window keeps your nowrap
  end)

  it("leaves item buffers alone when wrap = false", function()
    require("sprints.config").options.wrap = false
    local bufnr = util.named_scratch("sprints://I-nowrap-test", "sprints-item")
    vim.cmd("enew")
    vim.api.nvim_set_current_buf(bufnr)
    assert.is_false(vim.wo.wrap)
    require("sprints.config").options.wrap = true
  end)

  it("set_wrap(false) keeps lists to one row per item", function()
    vim.o.wrap = true
    vim.cmd("enew")
    util.set_wrap(0, false)
    assert.is_false(vim.wo.wrap)
  end)
end)
