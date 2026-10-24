# PowerShell helpers for Neovim on Windows. Add ONE line to your $PROFILE:
#     . "$env:LOCALAPPDATA\nvim\scripts\nv.ps1"
#
#   nv [args]     run nvim; if it crashes, fix the terminal, say what kind of crash it was, and kill
#                 the Roslyn / netcoredbg / API processes it left behind. Use it instead of `nvim`.
#   nv-recover    the same cleanup by hand (e.g. you ran plain `nvim` and the shell is now garbled)

. (Join-Path $PSScriptRoot 'dotnet-orphans.ps1')

function Reset-NvTerminal {
    # Undo modes a TUI may leave on when it dies: alt screen, hidden cursor, mouse reporting,
    # bracketed paste, focus events, kitty keyboard, Windows Terminal's win32-input-mode (the one
    # that makes every keypress come out as garbage).
    $e = [char]27
    [Console]::Write("$e[?1049l$e[?25h$e[?1000l$e[?1002l$e[?1003l$e[?1006l$e[?2004l$e[?1004l$e[?9001l$e[<u$e[0m$e[ q")
    try { [Console]::TreatControlCAsInput = $false } catch { }
    try { [Console]::CursorVisible = $true } catch { }
}

function Get-NvExitReason([int]$code) {
    $hex = '0x{0:X8}' -f $code
    switch ($hex) {
        '0xC0000005' { 'access violation (native crash: a C/C++ bug in nvim, a treesitter parser or a native plugin)' }
        '0xC00000FD' { 'stack overflow (runaway recursion, often in Lua or a parser)' }
        '0xC0000409' { 'fail-fast / buffer overrun detected (native crash)' }
        '0xC0000374' { 'heap corruption (native crash)' }
        '0xC000013A' { 'killed by Ctrl+C / console closed' }
        '0xC0000017' { 'out of memory' }
        default      { "exit code $code ($hex)" }
    }
}

function Invoke-NvCleanup {
    $state = Join-Path $env:LOCALAPPDATA 'nvim-data\dotnet-procs.json'
    $msg = Invoke-DotnetOrphans -StateFile $state -Kill -Quiet
    if ($msg) { Write-Host $msg -ForegroundColor Yellow } else { Write-Host 'No leftover .NET processes.' -ForegroundColor DarkGray }
}

function nv {
    & nvim @args
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $code -ne 1) {
        # 1 = a normal ":cq"-style error exit; anything else here is unusual
        Reset-NvTerminal
        Write-Host ''
        Write-Host ("Neovim exited abnormally: " + (Get-NvExitReason $code)) -ForegroundColor Red
        Write-Host 'Cleaning up. Inside nvim, :Doctor shows what it was doing just before.' -ForegroundColor DarkGray
        Invoke-NvCleanup
    }
}

function nv-recover {
    Reset-NvTerminal
    Invoke-NvCleanup
}
