# sync-settings.ps1 : one-way MERGE of shared\settings.json into acc1/acc2 settings.json
#   default = dry run (prints what would change, writes nothing)
#   -Apply  = backs up each account's file as settings.json.bak-<time>, then writes
# Rules: keys present in shared overwrite the account's value. Keys that exist only in the
# account (e.g. enabledPlugins) are KEPT. Nothing is ever deleted from an account file.
param([switch]$Apply)
$shared = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'shared\settings.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
foreach ($a in 'acc1','acc2') {
  $path = Join-Path $PSScriptRoot "$a\.claude\settings.json"
  $acc = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $changes = @()
  foreach ($p in $shared.PSObject.Properties) {
    $new = $p.Value | ConvertTo-Json -Depth 20 -Compress
    $cur = if ($acc.PSObject.Properties[$p.Name]) { $acc.($p.Name) | ConvertTo-Json -Depth 20 -Compress } else { $null }
    if ($new -ne $cur) { $changes += $p.Name; $acc | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
  }
  $kept = @($acc.PSObject.Properties.Name | Where-Object { -not $shared.PSObject.Properties[$_] })
  "== $a : " + $(if ($changes) { 'would change: ' + ($changes -join ', ') } else { 'no changes' }) + $(if ($kept) { ' | account-only keys kept: ' + ($kept -join ', ') })
  if ($Apply -and $changes) {
    Copy-Item $path ($path + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [IO.File]::WriteAllText($path, ($acc | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
    "   written (backup kept)"
  }
}
if (-not $Apply) { 'Dry run only. Re-run with -Apply to write.' }
