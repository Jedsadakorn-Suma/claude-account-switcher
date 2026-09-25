# launch.ps1 : run Claude Code under one sandbox account, in THIS window.
# On a plain start: claude1 / claude2 (i.e. launch.ps1 acc1 / acc2), any extra args pass through.
# On /exit: this window offers a one-key switch to the OTHER account, resuming the
# exact same conversation (--resume <the session's own id>) -- no folder guessing,
# so it stays correct even when several sessions are open in the same folder at once
# (see the README section "Bug: --continue picked the wrong session" for why that
# matters -- this tracks the session id THIS window actually got, never "whatever's
# newest in this folder").
#
# Only CLAUDE_CONFIG_DIR is overridden -- never USERPROFILE/HOME -- so git identity,
# .ssh, .npmrc, gh, etc. keep working exactly as they do outside the sandbox.
param(
    [Parameter(Mandatory)][ValidateSet('acc1', 'acc2')][string]$Acc,
    [Parameter(ValueFromRemainingArguments)]$Rest
)

. (Join-Path $PSScriptRoot 'pane-state.ps1')

function Get-CfgDir([string]$acc) { Join-Path (Join-Path $PSScriptRoot $acc) '.claude' }

# Start-Process -FilePath 'claude' fails ("%1 is not a valid Win32 application"): Windows'
# own resolution for a bare name picks a different one of the several npm shims (claude,
# claude.cmd, claude.ps1) than PowerShell's own `&` operator does, and can land on a script
# file instead of the real binary. Resolve the actual claude.exe explicitly (same relative
# path claude.cmd itself uses) so Start-Process gets a real Win32 executable, and so the
# pid Start-Process returns is the SAME pid Claude Code's own session registry uses.
# (Verified against a live Claude Code 2.1.282 process: npm's claude.cmd resolves to
# node_modules\@anthropic-ai\claude-code\bin\claude.exe -- this is an internal detail of
# that version's npm package layout, not a documented API, and may change.)
function Resolve-ClaudeExe {
    $cmd = Get-Command claude.cmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $candidate = Join-Path (Split-Path $cmd.Source -Parent) 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return 'claude'
}
$script:ClaudeExe = Resolve-ClaudeExe

# <cfg>\sessions\<pid>.json is Claude Code's own live-session registry (undocumented,
# version-specific -- observed on 2.1.282). It disappears when the session exits, so this
# only works while the process is alive, which is exactly the window we need it for.
function Wait-ForSessionId([string]$cfgDir, [int]$procId, [int]$timeoutSec = 12) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    $file = Join-Path $cfgDir "sessions\$procId.json"
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $file) {
            try {
                $o = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
                if ($o.sessionId) { return $o.sessionId }
            }
            catch {}
        }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Get-ResumeIdFromArgs($argList) {
    for ($i = 0; $i -lt $argList.Count - 1; $i++) {
        if ($argList[$i] -eq '--resume') { return $argList[$i + 1] }
    }
    return $null
}

$currentAcc = $Acc
# @($Rest) alone turns a null $Rest (no extra args passed) into a 1-element array
# containing $null, which Start-Process -ArgumentList then rejects. Filter it out.
$currentArgs = @($Rest | Where-Object { $null -ne $_ })
$cwd = (Get-Location).Path
$old = $env:CLAUDE_CONFIG_DIR

try {
    while ($true) {
        $cfg = Get-CfgDir $currentAcc
        $env:CLAUDE_CONFIG_DIR = $cfg

        if ($env:SANDBOX_DRYRUN) {
            "DRYRUN launch $currentAcc in $cwd args=[$($currentArgs -join ' ')] cfg=$cfg"
            return
        }

        # Splat so -ArgumentList is omitted entirely on a plain launch (empty array),
        # instead of passing an empty/null list Start-Process would reject.
        $startArgs = @{ FilePath = $script:ClaudeExe; NoNewWindow = $true; PassThru = $true; WorkingDirectory = $cwd }
        if ($currentArgs.Count -gt 0) { $startArgs.ArgumentList = $currentArgs }
        $proc = Start-Process @startArgs

        $knownId = Get-ResumeIdFromArgs $currentArgs
        $sessionId = if ($knownId) { $knownId } else { Wait-ForSessionId $cfg $proc.Id }
        if ($sessionId) { Save-PaneState -Acc $currentAcc -SessionId $sessionId -Cwd $cwd }

        $proc.WaitForExit()

        if (-not $sessionId) {
            # Couldn't identify the session (e.g. --version, or the registry write races us) --
            # nothing safe to resume, so just stop here instead of guessing.
            return
        }

        $otherAcc = if ($currentAcc -eq 'acc1') { 'acc2' } else { 'acc1' }
        Write-Host ''
        $ans = Read-Host "[$currentAcc] exited (session $($sessionId.Substring(0,8))). Press 's' + Enter to switch to $otherAcc and continue, or just Enter to stop"
        if ($ans -ne 's') { return }

        $currentAcc = $otherAcc
        $currentArgs = @('--resume', $sessionId)
    }
}
finally {
    $env:CLAUDE_CONFIG_DIR = $old
}
