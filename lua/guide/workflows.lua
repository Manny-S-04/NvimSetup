-- Workflow guides shown by F1 / <leader>H / :Guide. Add your own: copy a block, edit, save.
--
-- Each guide:
--   id        name for :Guide <id>
--   title     what you'd search for
--   contexts  when F1 shows it first: debug-stopped, debug-running, debug, tests, csharp, dotnet,
--             git, jira, errors, general
--   steps     { keys = "<F5>", text = "…" }   a mapping (checked by :Guide check, runnable with Enter)
--             { cmd = ":CSharpLsp", text = "…" } an Ex command
--             { text = "…" }                    a note
--             builtin = true  -> a Neovim default key (not checked)
--             buffer = true   -> only mapped inside a specific buffer (not checked globally)
return {
    -- ── debugging ────────────────────────────────────────────────────────────────────
    {
        id = "debug-paused",
        title = "Paused at a breakpoint — what now?",
        summary = "The ➜ line is the next line to run. Values show inline; Locals/Watch/Call Stack on the left.",
        contexts = { "debug-stopped" },
        steps = {
            { keys = "<F10>", text = "Step over (run this line)" },
            { keys = "<F11>", text = "Step into the call on this line" },
            { keys = "<S-F11>", text = "Step out (finish this method)" },
            { keys = "<F5>", text = "Continue to the next breakpoint" },
            { keys = "<C-F10>", text = "Run to the cursor line" },
            { keys = "<S-F9>", text = "QuickWatch the word / selection under the cursor", modes = { "n", "v" } },
            { keys = "<leader>dr", text = "Immediate window: evaluate or assign (x = 5)" },
            { keys = "<leader>dk", text = "Up the call stack (who called me)" },
            { keys = "<leader>dj", text = "Back down the call stack" },
            { keys = "<leader>du", text = "Show / hide the debug windows" },
            { keys = "<leader>z", text = "Zoom this window full-screen / back (a breakpoint hit un-zooms)" },
            { keys = "<S-F5>", text = "Stop debugging" },
            { keys = "<C-S-F5>", text = "Restart" },
        },
    },
    {
        id = "debug-start",
        title = "Debug a .NET API / app (F5)",
        summary = "Same flow as Visual Studio: breakpoints first, then F5.",
        contexts = { "dotnet", "csharp", "debug-running" },
        steps = {
            { keys = "<F9>", text = "Put a breakpoint on this line (red ●)" },
            { keys = "<F5>", text = "Start debugging. 1st time: pick project + launch profile (remembered)" },
            { text = "Wait for the build. Debug windows stay hidden while it runs and open when it pauses." },
            { text = "Hit the endpoint (browser / Postman / curl) — execution pauses on the ●, press F1 again." },
            { keys = "<C-F5>", text = "Run WITHOUT the debugger" },
            { keys = "<leader>nd", text = "Debug a different project / launch profile" },
            { keys = "<leader>nz", text = "Forget the remembered project/profile" },
            { keys = "<leader>da", text = "Attach to an already-running process instead" },
        },
    },
    {
        id = "debug-running",
        title = "Debugger is running (not paused)",
        contexts = { "debug-running" },
        steps = {
            { keys = "<F9>", text = "Add/remove a breakpoint — takes effect immediately" },
            { keys = "<leader>dp", text = "Pause right now (VS: Break All)" },
            { keys = "<leader>du", text = "Peek at the debug windows / program output (they auto-hide while running)" },
            { keys = "<leader>z", text = "Zoom this window full-screen / back" },
            { keys = "<S-F5>", text = "Stop debugging" },
            { keys = "<C-S-F5>", text = "Restart" },
            { text = "Breakpoint shows ○ instead of ●? That line has no code the debugger can bind to (or the build is stale)." },
        },
    },
    {
        id = "breakpoints",
        title = "Breakpoints: conditional, hit count, tracepoints",
        contexts = { "debug", "csharp" },
        steps = {
            { keys = "<F9>", text = "Toggle a normal breakpoint" },
            { keys = "<leader>dc", text = "Conditional: only stop when e.g. id == 42" },
            { keys = "<leader>dh", text = "Hit count: stop on the Nth hit" },
            { keys = "<leader>dl", text = "Tracepoint: log a message ({expr} interpolates), don't stop" },
            { keys = "<C-S-F9>", text = "Delete all breakpoints" },
            { text = "Glyphs: ● normal · ◆ conditional · ◉ log · ○ couldn't bind" },
        },
    },
    {
        id = "debug-broken",
        title = "Debugger won't start / port in use / stuck",
        summary = "Usually a leftover process from an earlier run or crash.",
        contexts = { "debug", "dotnet" },
        steps = {
            { cmd = ":DotnetCleanup", text = "Find and kill leftover netcoredbg / API / Roslyn processes" },
            { keys = "<leader>ns", text = "Stop projects easy-dotnet is running" },
            { keys = "<C-S-b>", text = "Build — a build error stops F5 from attaching" },
            { keys = "<leader>xq", text = "See the build errors" },
            { keys = "<leader>nz", text = "Forget the remembered startup project, then F5 to pick again" },
            { cmd = ":checkhealth easy-dotnet", text = "Check EasyDotnet / netcoredbg are installed", builtin = true },
        },
    },

    -- ── tests ────────────────────────────────────────────────────────────────────────
    {
        id = "tests",
        title = "Run / debug tests",
        contexts = { "tests", "dotnet" },
        steps = {
            { keys = "<leader>nt", text = "Test Explorer (right-hand side)" },
            { keys = "<leader>nu", text = "Run the test under the cursor (in a test .cs file)", buffer = true },
            { keys = "<leader>nU", text = "Run every test in this file", buffer = true },
            { keys = "<leader>nD", text = "Debug the test under the cursor (breakpoints work)", buffer = true },
            { keys = "<leader>nk", text = "Peek the failed test's stack trace", buffer = true },
            { keys = "<leader>nT", text = "Run all tests in the solution" },
            { keys = "<leader>tr", text = "neotest: run nearest test" },
            { keys = "<C-t>", text = "neotest: summary panel" },
        },
    },

    -- ── building ─────────────────────────────────────────────────────────────────────
    {
        id = "build",
        title = "Build and fix errors",
        contexts = { "dotnet", "csharp", "errors" },
        steps = {
            { keys = "<C-S-b>", text = "Build solution (errors go to the quickfix list)" },
            { keys = "<leader>nB", text = "Build one project" },
            { keys = "<leader>xq", text = "Build errors panel" },
            { keys = "<leader>xx", text = "Error List: all LSP diagnostics" },
            { keys = "<leader>ne", text = "Solution-wide errors & warnings (Roslyn)" },
            { keys = "<leader>e", text = "Show the error under the cursor" },
            { keys = "]q", text = "Next / [q previous error", builtin = true },
            { keys = "<leader>nx", text = "Restore NuGet packages" },
        },
    },

    -- ── code ─────────────────────────────────────────────────────────────────────────
    {
        id = "navigate",
        title = "Navigate code (definition, references, back)",
        contexts = { "csharp", "general" },
        steps = {
            { keys = "<F12>", text = "Go to definition" },
            { keys = "<C-o>", text = "Go BACK to where you were (VS: Ctrl+-)", builtin = true },
            { keys = "<C-i>", text = "Go forward again", builtin = true },
            { keys = "<A-F12>", text = "Peek definition in a popup" },
            { keys = "<S-F12>", text = "Find all references" },
            { keys = "<C-F12>", text = "Go to implementation" },
            { keys = "<leader>ds", text = "Symbols in this file (outline)" },
            { keys = "<leader>ci", text = "Who calls this? (call hierarchy)" },
            { keys = "<leader>ff", text = "Find file by name" },
            { keys = "<leader>fs", text = "Search text in the repo" },
            { keys = "<leader>hm", text = "Harpoon menu (Space 1-9 jumps to pinned files)" },
        },
    },
    {
        id = "edit-code",
        title = "Rename, quick fixes, format",
        contexts = { "csharp" },
        steps = {
            { keys = "<F2>", text = "Rename symbol everywhere" },
            { keys = "<C-.>", text = "Quick actions / refactorings (VS lightbulb)", modes = { "n", "v" } },
            { keys = "<leader>ca", text = "Same, if your terminal doesn't send Ctrl+.", modes = { "n", "v" } },
            { keys = "<C-k>", text = "Hover docs for the symbol" },
            { keys = "<leader>cf", text = "Format document" },
            { keys = "<leader>cl", text = "Run the CodeLens on this line (references / run test)" },
        },
    },
    {
        id = "lsp-broken",
        title = "IntelliSense slow / broken / no definitions",
        summary = "Roslyn takes a while on big solutions; F12 says 'No locations' until it has loaded the project.",
        contexts = { "csharp", "dotnet" },
        steps = {
            { cmd = ":CSharpLsp", text = "Which C# server is running right now" },
            { cmd = ":CSharpLsp fallback", text = "Switch to roslyn.nvim if easy-dotnet's server is stuck" },
            { cmd = ":Doctor", text = "Health report: servers, stray processes, last crash" },
            { cmd = ":LspRestart", text = "Restart the language server" },
            { cmd = ":DotnetCleanup", text = "Kill Roslyn copies left over from a crashed session" },
        },
    },
    {
        id = "nuget-ef",
        title = "NuGet, EF migrations, user secrets, new files",
        contexts = { "dotnet" },
        steps = {
            { keys = "<leader>np", text = "Add a NuGet package" },
            { keys = "<leader>no", text = "Outdated packages" },
            { keys = "<leader>nma", text = "EF: add migration" },
            { keys = "<leader>nmu", text = "EF: update database" },
            { keys = "<leader>nml", text = "EF: list migrations" },
            { keys = "<leader>nS", text = "User secrets" },
            { keys = "<leader>nn", text = "Add new item from a template" },
        },
    },

    -- ── git / jira ───────────────────────────────────────────────────────────────────
    {
        id = "git",
        title = "Git: review, stage, blame, history",
        contexts = { "git", "general" },
        steps = {
            { keys = "<leader>gd", text = "Changes view (diffview); Space gq closes it" },
            { keys = "]h", text = "Next change in this file ([h previous)", buffer = true },
            { keys = "<leader>gp", text = "Preview this change", buffer = true },
            { keys = "<leader>gs", text = "Stage this change", buffer = true },
            { keys = "<leader>gR", text = "Undo this change", buffer = true },
            { keys = "<leader>gb", text = "Blame this line", buffer = true },
            { keys = "<leader>gh", text = "History of this file" },
            { cmd = ":Git", text = "Fugitive status: s stage · u unstage · cc commit · = diff" },
            { cmd = ":History", text = "Show the commit for a ticket (:History CV-123)" },
        },
    },
    {
        id = "jira",
        title = "Jira tickets",
        contexts = { "jira" },
        steps = {
            { cmd = ":JiraBoard", text = "Open the board (CV)" },
            { cmd = ":JiraMine", text = "My open tickets" },
            { cmd = ":JiraFind", text = "Find tickets without JQL: pick project/status/type… (Space jf); :JiraFind <preset> reruns a saved one" },
            { cmd = ":JiraIssue", text = "Open a ticket by key (:JiraIssue CV-123)" },
            { keys = "<CR>", text = "In a list: open the ticket", buffer = true },
            { keys = "s", text = "In a ticket: change status", buffer = true },
            { keys = "c", text = "In a ticket: comment", buffer = true },
            { keys = "a", text = "In a ticket: assign to me (A unassigns)", buffer = true },
            { keys = "gx", text = "Open in the browser", buffer = true },
            { keys = "gp", text = "In a ticket: open its parent (gc lists its children)", buffer = true },
            { keys = "g?", text = "All ticket keys", buffer = true },
        },
    },
    {
        id = "jira-worklist",
        title = "Work through a parent's tickets (worklist)",
        summary = "Given CV-5 whose parent has the tickets you're meant to do: the parent's children become a harpoon list.",
        contexts = { "jira", "general" },
        steps = {
            { cmd = ":JiraWork", text = "Worklist = the parent's child tickets (:JiraWork CV-5, or W in a ticket)" },
            { keys = "<leader>jw", text = "Open the worklist (reorder / delete lines like harpoon)" },
            { keys = "<leader>jn", text = "Next ticket in the worklist" },
            { keys = "<leader>jp", text = "Previous ticket" },
            { keys = "W", text = "In a Jira list: make this whole list the worklist", buffer = true },
            { keys = "+", text = "In a list or ticket: add this ticket to the worklist", buffer = true },
            { cmd = ":JiraWorklist refresh", text = "Re-fetch statuses (✓ marks done tickets)" },
        },
    },

    -- ── recovery ─────────────────────────────────────────────────────────────────────
    {
        id = "after-crash",
        title = "Neovim crashed — clean up",
        summary = "Windows doesn't kill child processes when nvim dies, so Roslyn/netcoredbg/your API keep running.",
        contexts = { "general" },
        steps = {
            { cmd = ":DotnetCleanup", text = "Kill what the crashed session left behind (also runs at startup)" },
            { cmd = ":Doctor", text = "What was happening just before the crash" },
            { text = "Terminal garbled after a crash? Run  nv-recover  in PowerShell instead of restarting it." },
        },
    },
    {
        id = "help",
        title = "Finding things yourself",
        contexts = { "general" },
        steps = {
            { keys = "<F1>", text = "Guide for what you're doing right now" },
            { keys = "<leader>H", text = "Browse / search every guide" },
            { keys = "<leader>?", text = "Search every key mapping by what it does" },
            { cmd = ":Guide edit", text = "Add your own guide" },
            { cmd = ":Guide check", text = "Check guides still match your mappings" },
        },
    },
}
