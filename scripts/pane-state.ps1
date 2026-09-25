# pane-state.ps1 : dot-sourced by launch.ps1 and sw.ps1 so both agree on the same
# per-WINDOW (not per-folder) identity. Fixes a bug where two Claude sessions open
# in the same folder could get confused with each other -- see the README section
# "Bug: --continue picked the wrong session".
#
# Identity: Orca (github.com/stablyai/orca) sets $env:ORCA_PANE_KEY per pane already,
# so reuse it. A plain terminal window has no such thing, so generate one GUID the
# first time and keep it in $env:CC_PANE_ID for the life of that window only.

function Get-PaneStateFile {
    if (-not $env:CC_PANE_ID) {
        $env:CC_PANE_ID = if ($env:ORCA_PANE_KEY) { $env:ORCA_PANE_KEY } else { [guid]::NewGuid().ToString() }
    }
    $sha = [Security.Cryptography.SHA1]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($env:CC_PANE_ID))) -replace '-', '').Substring(0, 16)
    $dir = Join-Path $PSScriptRoot 'state'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory $dir | Out-Null }
    Join-Path $dir "pane-$hash.json"
}

function Save-PaneState {
    param([Parameter(Mandatory)][string]$Acc, [Parameter(Mandatory)][string]$SessionId, [Parameter(Mandatory)][string]$Cwd)
    $file = Get-PaneStateFile
    $obj = [pscustomobject]@{ acc = $Acc; sessionId = $SessionId; cwd = $Cwd; updatedAt = (Get-Date).ToString('s') }
    [IO.File]::WriteAllText($file, ($obj | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
}

function Get-PaneState {
    $file = Get-PaneStateFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $null }
}
