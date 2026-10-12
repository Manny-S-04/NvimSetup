local dir = vim.fn.expand('~/AI/pair/nvim') -- C:\Users\man20\AI\pair on Windows, ~/AI/pair on Fedora
return {
  dir = dir,
  cond = vim.fn.isdirectory(dir) == 1, -- skip quietly on machines without pair
  lazy = false,
  config = function()
    require('pair').setup({ complete = { accept = '<C-y>', accept_line = '<M-y>' } })
  end,
  keys = {
    { '<leader>pa', ':PairAsk<CR>', mode = { 'n', 'v' } },
    { '<leader>pj', '<cmd>PairJobs<CR>' },
    { '<leader>pl', '<cmd>PairLast<CR>' },
  },
}
