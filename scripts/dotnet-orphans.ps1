# Finds .NET tooling processes left behind by a Neovim session that died (Roslyn, EasyDotnet,
# netcoredbg, the API you were debugging...). Windows does not kill child processes when their
# parent dies, so after an nvim crash these keep running: the API holds its port, netcoredbg holds
# the console, Roslyn eats RAM.
#
# Used by lua/dotnet-procs.lua (startup sweep, :DotnetCleanup) and by the nv / nv-recover
# PowerShell functions. Dot-source it, then call Invoke-DotnetOrphans.
#
# "Orphan" = its parent process no longer exists (or the parent PID was reused by a newer process).
# Only orphans that are clearly ours get auto-killed:
#   tooling: Roslyn / EasyDotnet / netcoredbg / BuildHost / testhost
#   apps:    an exe under <a .NET repo nvim was opened in>\...\bin\Debug|Release\, or a recorded debug target
# MSBuild node-reuse servers and VBCSCompiler are deliberately detached and are left alone.

function Invoke-DotnetOrphans {
    param(
        [int]$Self = 0,          # pid of the calling nvim: its own children are never touched
        [string]$StateFile = '', # nvim-data\dotnet-procs.json (roots + debug targets)
        [switch]$Kill,           # kill the auto-kill candidates
        [switch]$KillAll,        # kill every listed process that isn't this nvim's own
        [switch]$Quiet           # with -Kill: print only a one-line summary instead of JSON
    )

    $roots = @(); $programs = @()
    if ($StateFile -and (Test-Path -LiteralPath $StateFile)) {
        try {
            $st = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
            if ($st.roots) { $roots = @($st.roots) }
            if ($st.programs) { $programs = @($st.programs) }
        } catch { }
    }

    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, ExecutablePath, CreationDate)
    $byId = @{}
    foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }

    $toolingName = '^(netcoredbg|Microsoft\.CodeAnalysis\.LanguageServer|EasyDotnet|roslyn|Microsoft\.CodeAnalysis\.Workspaces\.MSBuild\.BuildHost|testhost)'
    $toolingCmd = 'EasyDotnet|Microsoft\.CodeAnalysis\.LanguageServer|roslyn-language-server|netcoredbg|BuildHost|testhost'
    $leaveAlone = 'MSBuild\.dll|/nodemode|VBCSCompiler|dotnet-counters|dotnet-trace'

    function Test-Mine([object]$p) {
        if ($Self -le 0) { return $false }
        $cur = $p; $n = 0
        while ($cur -and $n -lt 25) {
            if ([int]$cur.ProcessId -eq $Self) { return $true }
            $parent = $byId[[int]$cur.ParentProcessId]
            if (-not $parent -or $parent.CreationDate -gt $cur.CreationDate) { return $false }
            $cur = $parent; $n++
        }
        return $false
    }

    $out = New-Object System.Collections.ArrayList
    foreach ($p in $all) {
        $name = [string]$p.Name
        $cmd = [string]$p.CommandLine
        $exe = [string]$p.ExecutablePath
        if ($cmd -match $leaveAlone) { continue }

        $reason = $null
        if ($name -match $toolingName -or ($name -eq 'dotnet.exe' -and $cmd -match $toolingCmd)) {
            $reason = 'tooling'
        } else {
            foreach ($prog in $programs) {
                if (-not $prog) { continue }
                $stem = [IO.Path]::Combine([IO.Path]::GetDirectoryName($prog), [IO.Path]::GetFileNameWithoutExtension($prog))
                if (($exe -and [string]::Equals([IO.Path]::ChangeExtension($exe, $null).TrimEnd('.'), $stem, [StringComparison]::OrdinalIgnoreCase)) -or ($cmd -and $cmd.IndexOf($prog, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                    $reason = 'debug target'; break
                }
            }
            if (-not $reason) {
                foreach ($r in $roots) {
                    if (-not $r) { continue }
                    $rr = $r.TrimEnd('\', '/') + '\'
                    if ($exe -and $exe.StartsWith($rr, [StringComparison]::OrdinalIgnoreCase) -and $exe -match '\\bin\\(Debug|Release)\\') { $reason = 'app built here'; break }
                    if ($name -eq 'dotnet.exe' -and $cmd -match '\s(run|watch)\b' -and $cmd.IndexOf($r, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $reason = 'dotnet run'; break }
                }
            }
        }
        if (-not $reason) { continue }

        $parent = $byId[[int]$p.ParentProcessId]
        $orphan = (-not $parent) -or ($parent.CreationDate -gt $p.CreationDate)
        $mine = Test-Mine $p
        [void]$out.Add([pscustomobject]@{
            pid      = [int]$p.ProcessId
            ppid     = [int]$p.ParentProcessId
            name     = $name
            reason   = $reason
            orphan   = [bool]$orphan
            mine     = [bool]$mine
            autokill = [bool]($orphan -and -not $mine)
            started  = if ($p.CreationDate) { $p.CreationDate.ToString('yyyy-MM-dd HH:mm') } else { '' }
            cmd      = if ($cmd.Length -gt 200) { $cmd.Substring(0, 200) } else { $cmd }
            killed   = $false
        })
    }

    if ($Kill -or $KillAll) {
        foreach ($o in $out) {
            if (($KillAll -and -not $o.mine) -or $o.autokill) {
                # /T: take the whole tree (netcoredbg -> your API, dotnet run -> app.exe)
                & taskkill.exe /PID $o.pid /T /F *> $null
                $o.killed = ($LASTEXITCODE -eq 0) -or -not (Get-Process -Id $o.pid -ErrorAction SilentlyContinue)
            }
        }
    }

    if ($Quiet) {
        $k = @($out | Where-Object { $_.killed })
        if ($k.Count -gt 0) {
            'Killed ' + $k.Count + ' leftover process(es): ' + (($k | ForEach-Object { $_.name + ' ' + $_.pid }) -join ', ')
        }
        return
    }
    ConvertTo-Json -InputObject @($out) -Compress -Depth 3
}
