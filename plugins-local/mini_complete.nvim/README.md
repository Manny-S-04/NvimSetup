# mini_complete.nvim

LSP completion in a **one-line bar at the bottom of the screen** — minibuffer / vertico style —
instead of a popup that covers the code you're typing next to.

```
  var task = Tas▌
  ──────────────────────────────────────────────────────────────────────────────
  Task  Task<>  TaskAsyncEnumerableExtensions  TaskCanceledException  TaskCompletionSource …
```

No completion framework underneath: it talks to Neovim's built-in LSP client directly.

## Features

- Candidates from **every** attached LSP server, plus [LuaSnip](https://github.com/L3MON4D3/LuaSnip)
  snippets (optional)
- Accept does what the server intended: `textEdit` ranges, `itemDefaults`, snippet expansion
  (`${1:arg}` placeholders), **auto-imports** (`additionalTextEdits` — e.g. `using System.Text.Json;`)
  and server commands (Roslyn's complex edits)
- Opens after member-access tokens (`obj.`) with nothing typed yet
- Documentation window above the bar: toggle, scroll, or jump into it to read/yank
- Debounced, and in-flight requests are cancelled as you type
- Closes when you move away; doesn't reopen on the word you just completed
- Fallthrough keys: when the bar is closed every mapped key does its normal job, macros and `.`
  repeat included
- Follows your colorscheme (or set your own colours)

## Requirements

- Neovim **0.11+**
- An LSP server attached to the buffer
- Optional: LuaSnip

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "<your-github-user>/mini_complete.nvim",
  event = "InsertEnter",
  opts = {},
}
```

Other plugin managers: add the repo and call `require("mini_complete").setup({})`.

Use it **instead of** nvim-cmp / blink.cmp / built-in `vim.lsp.completion` autotrigger — two
completion UIs will fight over `<CR>`.

Advertise snippet support so servers send snippets (and full function signatures):

```lua
local caps = vim.lsp.protocol.make_client_capabilities()
caps.textDocument.completion.completionItem.snippetSupport = true
vim.lsp.config("*", { capabilities = caps })
```

## Default keys (insert mode)

| Key | Action |
|---|---|
| `<C-j>` / `<C-k>` | next / previous candidate |
| `<CR>` | accept |
| `<Esc>` | close the bar (and leave insert mode as usual) |
| `<F6>` | toggle documentation |
| `<F7>` | jump into the documentation window (`q` / `<Esc>` to come back) |
| `<C-f>` / `<C-b>` | scroll documentation |

Every key falls through to its normal behaviour when the bar (or the docs window) isn't open.

## Configuration

Defaults:

```lua
require("mini_complete").setup({
  debounce_ms = 30,
  min_prefix = 1,                 -- word characters before the bar opens
  -- open right after these tokens (when the server also advertises the trigger character);
  -- servers advertise far more ("(", ",", " " ...), which would open the bar constantly.
  -- Lua users may want ":" too. false to disable.
  trigger_characters = { ".", "->", "::" },
  resolve_timeout_ms = 300,       -- max wait for completionItem/resolve on accept
  enabled = function(bufnr)       -- false = no completion in this buffer
    local bt = vim.bo[bufnr].buftype
    return bt == "" or bt == "acwrite"
  end,
  exclude_filetypes = {},
  luasnip = true,                 -- list LuaSnip snippets, expand LSP snippets with LuaSnip
  notify_on_attach = false,       -- vim.notify when a completion server attaches
  docs = { max_height = 12, border = "rounded" },
  keymaps = {                     -- set any to false to leave that key alone
    next = "<C-j>",
    prev = "<C-k>",
    accept = "<CR>",
    cancel = "<Esc>",
    toggle_docs = "<F6>",
    focus_docs = "<F7>",
    scroll_docs_down = "<C-f>",
    scroll_docs_up = "<C-b>",
    snippet_next = false,         -- e.g. "<C-l>": next LuaSnip placeholder
    snippet_prev = false,         -- e.g. "<C-h>"
  },
  highlights = {},                -- overrides, see below
})
```

### Highlights

| Group | Default link |
|---|---|
| `MiniCompleteNormal` | `Pmenu` |
| `MiniCompleteSelected` | `PmenuSel` |
| `MiniCompleteSnippet` | `Special` |
| `MiniCompleteSnippetSelected` | `PmenuSel` |
| `MiniCompleteDocNormal` | `NormalFloat` |
| `MiniCompleteDocBorder` | `FloatBorder` |

Override in `setup` (re-applied after every `:colorscheme`):

```lua
highlights = {
  MiniCompleteSelected = { bg = "#45475a", fg = "#f5e0dc", bold = true },
}
```

## API

```lua
local mc = require("mini_complete")
mc.is_visible()     -- bar open?
mc.select_next()    mc.select_prev()
mc.accept()         mc.cancel()
mc.toggle_docs()    mc.focus_docs()
```

## Troubleshooting

`:checkhealth mini_complete` lists the running completion servers and whether LuaSnip is used.

The bar and docs live in hidden scratch buffers named `mini-complete://bar` and
`mini-complete://docs` (visible in `:ls!`). They are `nofile` and unmodifiable, so `:wall` and
friends ignore them.

## How it works

1. `TextChangedI` → debounce → `textDocument/completion` to all attached servers
   (`vim.lsp.buf_request_all`), cancelling the previous request.
2. Items are merged with the list's `itemDefaults`, filtered by `filterText`/`label` against the word
   before the cursor, LuaSnip snippets are added, and everything is sorted by `sortText`.
3. On accept: resolve the item if the server supports it (to get auto-import edits), delete the typed
   word, apply `additionalTextEdits` while an extmark tracks the cursor position, insert the
   `textEdit`/`insertText` (expanding snippets), then run the item's `command`.
