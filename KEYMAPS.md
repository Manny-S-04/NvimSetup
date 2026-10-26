# Neovim for .NET — keymap cheat sheet

Visual Studio keys where a terminal can send them, `<leader>` (Space) fallbacks for the rest.
Forgot one? **Space ?** searches every mapping by description (e.g. type `definition` → `<F12>`).

## Stuck? Find out yourself

| Key / command | Does |
|---|---|
| `F1` | Guide for what you're doing *right now* — paused at a breakpoint, debugging, in C#, tests, git, Jira. `Enter` on a line runs that key, `p` pins it in the corner (follows you as you step), `a` browses all |
| `Space H` | Browse / fuzzy-search every how-to ("breakpoint", "port in use", "rename"…) |
| `Space ?` | Search every key mapping by what it does |
| statusline | While debugging, the keys you need right now are shown bottom-right |
| `:Guide edit` / `:Guide check` | Add your own how-to / check the guides still match your mappings |
| `:Doctor` | Language servers, leftover processes, what nvim was doing before the last crash |
| `:DotnetCleanup` | Kill Roslyn / netcoredbg / your API left running by a crashed session (runs automatically at startup) |
| `nv` (PowerShell) | Run nvim via this instead of `nvim`: after a crash it fixes the terminal and cleans up. Setup: add `. "$env:LOCALAPPDATA\nvim\scripts\nv.ps1"` to `$PROFILE` |

## One-time setup per machine

```powershell
dotnet tool install -g EasyDotnet       # build/run/test/debug server for easy-dotnet.nvim
```
Roslyn (`roslyn-language-server`) is installed automatically by easy-dotnet the first time you open a
`.cs` file. Run `:checkhealth easy-dotnet` if anything looks off.

## Debugging

| Key | Visual Studio | Does |
|---|---|---|
| `F5` | Start / Continue | First time: pick project + launch profile (remembered after that) |
| `Ctrl+F5` | Start without debugging | Run the remembered project + profile |
| `Shift+F5` | Stop | |
| `Ctrl+Shift+F5` | Restart | |
| `F9` / `Space b` | Toggle breakpoint | |
| `Space dc` / `dh` / `dl` | Breakpoint conditions / hit count / actions | Conditional · hit-count · tracepoint (logs, doesn't stop) |
| `Ctrl+Shift+F9` | Delete all breakpoints | |
| `F10` / `F11` / `Shift+F11` | Step over / into / out | |
| `Ctrl+F10` | Run to cursor | |
| `Shift+F9` | QuickWatch | Evaluate the word/selection under the cursor |
| `Space dr` | Immediate window | REPL: evaluate, or assign (`x = 5`) |
| `Space du` | Debug windows | Locals · Watch · Call Stack · Breakpoints (left), Output + Immediate (bottom) |
| `Space dk` / `dj` | Call stack up/down | |
| `Space dp` | Break All | Pause the running program |
| `Space da` | Attach to process | |

Variable values also appear inline next to the code while stopped.

## Build / run / test

| Key | Does |
|---|---|
| `Ctrl+Shift+B` / `Space nb` | Build solution → errors in the quickfix list (`Space xq`) |
| `Space nB` | Build one project |
| `Space nr` / `nR` | Run default project / pick project + profile |
| `Space nd` | Debug: pick project + profile again |
| `Space nz` | Forget the remembered project/profile |
| `Space nw` | `dotnet watch` (hot reload) |
| `Space ns` | Stop running projects |
| `Space nq` | Show/hide build & run output |
| `Space nc` / `nx` | Clean / restore |
| `Space nt` | **Test Explorer** (right side; inside it `Space R` runs all, `o` expands, `q` closes) |
| `Space nT` | Run every test in the solution |
| `Space nu` / `nU` / `nD` | In a test file: run test under cursor / all in file / debug test under cursor |
| `Space nk` | Peek a failed test's stack trace |

Test files also get CodeLens above each test: `Run Test | Debug Test` (`Space cl` on that line).

## Solution & packages

| Key | Does |
|---|---|
| `Space np` / `nP` | NuGet: add / remove package |
| `Space no` | Show outdated packages (inline, in the .csproj) |
| `Space nS` | Manage user secrets |
| `Space nn` | Add new item (class, interface, controller… from `dotnet new` templates) |
| `Space nN` | New project |
| `Space ne` | Solution-wide errors & warnings |
| `Space nma` / `nmr` / `nmu` / `nml` | EF Core: add migration / remove last / update database / list |

## Code navigation & editing

| Key | Visual Studio | |
|---|---|---|
| `F12` | Go to definition | |
| `Alt+F12` | Peek definition | Floating preview |
| `Shift+F12` | Find all references | |
| `Ctrl+F12` | Go to implementation | |
| `F2` | Rename | |
| `Ctrl+.` / `Space ca` | Quick actions & refactorings | Includes Roslynator fixes |
| `Ctrl+k` | Quick info | Hover docs |
| `Space cf` | Format document | |
| `Space ci` / `co` | Call hierarchy | Callers / callees |
| `Ctrl+o` / `Ctrl+i` | Navigate backward / forward | Vim's jumplist |

Completion (insert mode, mini_complete): `Ctrl+j`/`Ctrl+k` move, `Enter` accept, `F6` docs,
`F7` jump into docs, `Ctrl+l`/`Ctrl+h` next/previous snippet placeholder. Typing `obj.` opens the list.

## Lists, Git, TODOs

| Key | Does |
|---|---|
| `Space xx` / `xb` | Error List: all files / this file |
| `Space xq` | Build errors |
| `Space xs` | Document outline |
| `Space xt` | Task List (TODO/FIXME/HACK); `]t` / `[t` jump between them |
| `]h` / `[h` | Next / previous changed hunk |
| `Space gp` / `gs` / `gR` | Preview / stage / undo hunk |
| `Space gb` / `gB` | Blame line / toggle inline blame |
| `Space gd` / `gh` / `gq` | Git changes diff view / file history / close |

## Not covered yet

- **WPF / XAML**: parked until you work on WPF again.
- **.http request files**: kulala.nvim needs Neovim 0.12 (add it when you upgrade).
- **Edit and Continue**: not available outside Visual Studio; use `dotnet watch` (`Space nw`).
