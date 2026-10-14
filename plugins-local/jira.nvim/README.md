# jira.nvim

Work with Jira tickets without leaving Neovim: list your issues, open any ticket, change its status,
comment, and assign — against **Jira Cloud** or **Jira Server / Data Center**.

```
:JiraMine
# My issues

PROJ-1   To Do        Audit endpoint times out
PROJ-2   In Progress  Add retry to payment client
```

## Features

- `:JiraMine` / `:JiraSearch <JQL>` — issue lists (any JQL), status coloured by category
- `:JiraBoard [ID]` — exactly what a board page shows: the active sprint on a scrum board, open work
  on a kanban board, in board order
- `:JiraIssue [KEY]` — open a ticket; with no argument it uses the key under the cursor
  (commit messages, branch names, TODO comments)
- In a ticket: change status (only the transitions your workflow allows), comment, assign to me,
  unassign, open in browser
- Cloud and Server/DC from one codebase — the API version, comment format (ADF vs plain text) and
  user identity (accountId vs username) are picked automatically
- Non-blocking: all requests run in the background
- Your token never appears in the process list (it is passed to curl on stdin)
- `:checkhealth jira` tells you exactly what's missing

## Requirements

- Neovim **0.10+**
- `curl` on `PATH` (Windows 10+ ships `curl.exe`)
- A Jira API token (Cloud) or Personal Access Token (Server/DC)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "<your-github-user>/jira.nvim",
  cmd = { "Jira", "JiraMine", "JiraIssue", "JiraSearch", "JiraBoard", "JiraRefresh" },
  opts = {},
}
```

Other plugin managers: add the repo and call `require("jira").setup({})`.

## Credentials

Keep credentials out of your dotfiles — by default they are read from the environment:

| Variable | Cloud | Server / Data Center |
|---|---|---|
| `JIRA_URL` | `https://yourco.atlassian.net` | `https://jira.yourco.com` |
| `JIRA_EMAIL` | your Atlassian login email | leave unset |
| `JIRA_API_TOKEN` | API token | Personal Access Token |

**Cloud token:** <https://id.atlassian.com/manage-profile/security/api-tokens> → *Create API token*.
Use the plain token, not *"with scopes"* — scoped tokens only work through the `api.atlassian.com`
gateway URL.

**Server/DC token:** your avatar → *Profile* → *Personal Access Tokens*.

Setting them permanently:

```sh
# Windows (PowerShell / cmd) — reopen your terminal afterwards
setx JIRA_URL "https://yourco.atlassian.net"
setx JIRA_EMAIL "you@yourco.com"
setx JIRA_API_TOKEN "..."

# macOS / Linux — in ~/.zshrc, ~/.bashrc, or a secrets manager
export JIRA_URL="https://yourco.atlassian.net"
export JIRA_EMAIL="you@yourco.com"
export JIRA_API_TOKEN="..."
```

Then run `:checkhealth jira`.

## Configuration

Everything is optional; these are the defaults. Explicit options win over environment variables.

```lua
require("jira").setup({
  url = nil,        -- default: $JIRA_URL
  email = nil,      -- default: $JIRA_EMAIL (Cloud only; omit for a Server/DC PAT)
  api_token = nil,  -- default: $JIRA_API_TOKEN
  -- "cloud" | "server" | nil. nil = *.atlassian.net is Cloud, anything else Server/DC.
  deployment = nil,
  timeout = 10000,  -- ms per request
  jql_mine = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  max_results = 50,
  -- Board :JiraBoard opens with no argument: the number in .../boards/19. nil = pick from a list.
  board = nil,
  -- Sprint field. Cloud: customfield_10020. Server/DC: varies per instance — find it at
  -- <url>/rest/api/2/field (the field whose schema.custom ends in ":gh-sprint").
  sprint_field = "customfield_10020",
  open_cmd = "split", -- "split" | "vsplit" | "tabnew" | "edit"
  keymaps = {       -- buffer-local; set any to false to disable
    issue = {
      close = "q", refresh = "r", status = "s", comment = "c",
      assign_me = "a", unassign = "A", browser = "gx", help = "g?",
    },
    list = { open = "<CR>", browser = "gx", refresh = "r", close = "q" },
  },
})
```

## Usage

| Command | |
|---|---|
| `:JiraMine` | Your open issues (`jql_mine`) |
| `:JiraSearch <JQL>` | Any search, e.g. `:JiraSearch project = PROJ AND sprint in openSprints()` |
| `:JiraBoard [ID]` | A board's current view. `ID` is the number in `…/boards/19` (a pasted board URL works too); with no `ID`, uses `board` from the config, or lets you pick from your boards |
| `:JiraIssue [KEY]` | Open an issue (defaults to the key under the cursor) |
| `:JiraRefresh` | Refresh the current issue buffer |
| `:Jira` | Help, and which instance you're connected to |

In an **issue** buffer: `s` status · `c` comment · `a` assign to me · `A` unassign · `gx` browser ·
`r` refresh · `q` close · `g?` help.

In a **list** buffer: `<CR>` open · `gx` browser · `r` refresh · `q` close.

**Boards** use the Jira Software Agile API (`/rest/agile/1.0`), which Cloud and Server/DC both have.
A scrum board shows `sprint in openSprints()` and the sprint name and end date in the title.
A kanban board shows unfinished work plus anything resolved in the last 14 days, close to what
Jira's own board shows. Lists stop at 500 issues.

**Comments** open in a scratch buffer: write Markdown-ish text (blank line = new paragraph),
`:w` to post, `:q!` to cancel. If posting fails, your text stays in the buffer.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `HTTP 401` | Wrong email/token, a *scoped* Cloud token, or your org has disabled API tokens |
| `HTTP 403` on an action | Your Jira role can't do that on this project (same as in the browser) |
| No *Sprint* line | Set `sprint_field` (Server/DC) |
| `curl exited with code 6/7/35/60` | DNS / connection / TLS — VPN or corporate proxy (curl honours `HTTPS_PROXY`) |

## Development

```
jira.nvim/
├── lua/jira/
│   ├── init.lua        setup()
│   ├── config.lua      defaults, env, Cloud/Server detection
│   ├── commands.lua    user commands
│   ├── health.lua      :checkhealth jira
│   ├── adf.lua         Atlassian Document Format -> text
│   ├── api/            HTTP only: no buffers or windows
│   │   ├── auth.lua    Basic (email+token) or Bearer (PAT)
│   │   ├── client.lua  curl transport, sync or async
│   │   └── issues.lua  get/search/transitions/comment/assign
│   └── ui/             buffers, keymaps, rendering
└── tests/              plenary.nvim specs
```

API functions take an optional trailing callback: with it they are async (`cb(value, err)` on the
main loop), without it they block and return `value, err` — handy in tests and scripts.

Run the tests from the plugin root (plenary is cloned to `$PLENARY_DIR`, default `/tmp/plenary.nvim`):

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', sequential = true }"
```
