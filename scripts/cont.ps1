# cont.ps1 : continue a saved session inside the current terminal (e.g. an Orca pane)
#   cont            list saved sessions
#   cont N [1|2]    cd to session N's folder and run: claude1/claude2 --resume <id>
# Refuses while the original process is still alive (two writers on one session file would corrupt it), use -Force to override.
param([int]$N = 0, [ValidateSet('1','2','')][string]$Acc = '', [switch]$Force)
$u8 = [Text.Encoding]::UTF8
$file = "$PSScriptRoot\handoff\latest.json"
if (-not (Test-Path $file)) { 'No snapshot. Run handoff-save.ps1 first.'; return }
$parsed = [IO.File]::ReadAllText($file, $u8) | ConvertFrom-Json
$rows = @($parsed | ForEach-Object { $_ })
if ($N -lt 1) {
  for ($i = 0; $i -lt $rows.Count; $i++) { $r = $rows[$i]; '{0,2}. [{1}] {2,-8} {3}  ({4})' -f ($i+1), $r.store, $r.sessionId.Substring(0,8), $r.cwd, $r.name }
  'Use: cont N 1|2'; return
}
$r = $rows[$N-1]; if (-not $r) { "No entry $N"; return }
if (-not $Acc) { $Acc = Read-Host 'Account to resume with (1 or 2)' }
if ($Acc -notin '1','2') { 'Cancelled.'; return }
$live = foreach ($d in @("$env:USERPROFILE\.claude", "$PSScriptRoot\acc1\.claude", "$PSScriptRoot\acc2\.claude")) {
  if (Test-Path "$d\sessions") { Get-ChildItem "$d\sessions" -File -Filter *.json | ForEach-Object { try { $o = [IO.File]::ReadAllText($_.FullName, $u8) | ConvertFrom-Json; if ($o.sessionId -eq $r.sessionId -and (Get-Process -Id $o.pid -ErrorAction SilentlyContinue)) { $o } } catch {} } }
}
if ($live -and -not $Force) { "Session $($r.sessionId.Substring(0,8)) is still running (pid $($live[0].pid)). /exit it first, or use -Force."; return }
# make sure the transcript is visible to the sandbox accounts (copy from the real store; original stays untouched)
$src = Get-ChildItem "$env:USERPROFILE\.claude\projects" -Recurse -Filter "$($r.sessionId).jsonl" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($src) {
  $projDir = $src.Directory.Name
  $dstDir = "$PSScriptRoot\shared\projects\$projDir"
  $dst = Join-Path $dstDir $src.Name
  $need = -not (Test-Path -LiteralPath $dst) -or ((Get-Item -LiteralPath $dst).Length -lt $src.Length)
  if ($need) {
    if ($env:SANDBOX_DRYRUN) { "DRYRUN would copy $([math]::Round($src.Length/1MB,1)) MB -> shared\projects\$projDir" }
    else {
      New-Item -ItemType Directory -Force $dstDir | Out-Null
      Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
      $sub = Join-Path $src.Directory.FullName $r.sessionId
      if (Test-Path -LiteralPath $sub) { Copy-Item -LiteralPath $sub -Destination $dstDir -Recurse -Force }
      "Copied transcript to shared\projects\$projDir"
    }
  }
}
Set-Location -LiteralPath $r.cwd
"cont: $($r.cwd) -> acc$Acc  --resume $($r.sessionId.Substring(0,8))"
& "$PSScriptRoot\launch.ps1" "acc$Acc" '--resume' $r.sessionId
