# handoff-save.ps1 : snapshot every LIVE Claude session (real config + acc1 + acc2) to handoff\latest.json
# Run it while the sessions are still open; the live registry entry disappears when a session exits.
$u8 = New-Object Text.UTF8Encoding($false)
$stores = @{ real = "$env:USERPROFILE\.claude"; acc1 = "$PSScriptRoot\acc1\.claude"; acc2 = "$PSScriptRoot\acc2\.claude" }
$rows = @()
foreach ($s in $stores.GetEnumerator()) {
  $dir = Join-Path $s.Value 'sessions'
  if (-not (Test-Path $dir)) { continue }
  foreach ($f in Get-ChildItem $dir -File -Filter *.json) {
    try { $o = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
    if (-not $o.pid -or -not (Get-Process -Id $o.pid -ErrorAction SilentlyContinue)) { continue }
    $rows += [pscustomobject]@{ store = $s.Key; pid = $o.pid; sessionId = $o.sessionId; cwd = $o.cwd; name = $o.name; status = $o.status }
  }
}
[IO.File]::WriteAllText("$PSScriptRoot\handoff\latest.json", (ConvertTo-Json -InputObject @($rows) -Depth 5), $u8)
"Saved $($rows.Count) live session(s) to handoff\latest.json"
$rows | ForEach-Object { '{0,-5} pid={1,-6} {2,-8} {3,-40} {4}' -f $_.store, $_.pid, $_.sessionId.Substring(0,8), $_.cwd, $_.name }
