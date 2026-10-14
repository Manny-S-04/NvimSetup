@echo off
cd /d "%~dp0"
echo === nvim config: commit and push ===
git add -A -- . ":!push-nvim.cmd"
git status --short
git commit -m "Add .NET/debugger/VS keymaps, keymap search, :JiraBoard" -m "Adds the files the previous commit left untracked (vs-keymaps, csharp-lsp, keymap-search, dotnet, debug, qol, KEYMAPS.md) and jira.nvim :JiraBoard." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01HqA4tTWqfrFz5KkZZpo6h7"
git push
echo.
git log --oneline -1
git status -sb
echo === done, press any key ===
pause >nul
(goto) 2>nul & del "%~f0"
