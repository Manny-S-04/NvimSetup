vim.cmd("set expandtab")
vim.cmd("set tabstop=4")
vim.cmd("set softtabstop=4")
vim.cmd("set shiftwidth=4")
vim.cmd("set ignorecase")
vim.cmd("set smartcase")
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("USERPROFILE") .. "/.vim/undodir"
vim.opt.undofile = true
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")
vim.opt.updatetime = 50
vim.opt.clipboard:append { "unnamed", "unnamedplus" }
vim.g.mapleader = " "

vim.diagnostic.config({
    virtual_lines = true,
    virtual_text = false,
    float = {
        border = "rounded",
        source = false,
    },
    signs = true,
    update_in_insert = false,
})

vim.api.nvim_set_keymap(
    "n",
    "<leader>e",
    "<cmd>lua vim.diagnostic.open_float()<CR>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<f2>",
    "<cmd>lua vim.lsp.buf.rename()<CR>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<A-Down>",
    "<cmd>m +1<CR>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<A-Up>",
    "<cmd>m -2<CR>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "v",
    "<A-Down>",
    ":m '>+1<CR>gv=gv",
    { noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
    "v",
    "<A-Up>",
    ":m '<-2<CR>gv=gv",
    { noremap = true, silent = true }
)

vim.api.nvim_set_keymap(
    "n",
    "<PageUp>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<PageDown>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<s-Up>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "n",
    "<s-Down>",
    "<Nop>",
     { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "i",
    "<PageUp>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "i",
    "<PageDown>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "i",
    "<s-Up>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "i",
    "<s-Down>",
    "<Nop>",
     { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "v",
    "<s-Up>",
    "<Nop>",
    { noremap = true, silent = true}
)

vim.api.nvim_set_keymap(
    "v",
    "<s-Down>",
    "<Nop>",
     { noremap = true, silent = true}
)
