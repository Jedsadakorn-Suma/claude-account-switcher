# sw.ps1 : manual fallback to switch THIS window's account after you've already exited claude
# without using the built-in switch prompt (e.g. you exited a while ago). Prefer just pressing
# 's' at the "exited" prompt from launch.ps1 -- that path is always exact.
#
# This used to relaunch with --continue (whatever conversation is newest in the current
# folder), which is wrong when several sessions share a folder -- see the README section
# "Bug: --continue picked the wrong session". Now it resumes THIS window's own last-known
# session id instead, via pane-state.ps1 -- the same per-window identity launch.ps1 tracks,
# keyed by $env:ORCA_PANE_KEY (Orca panes) or a per-window GUID (plain terminal windows),
# never by folder.
param([ValidateSet('1', '2', '')][string]$To = '')

. (Join-Path $PSScriptRoot 'pane-state.ps1')

$state = Get-PaneState
if (-not $state -or -not $state.sessionId) {
    'No session recorded for this window yet. Run claude1 or claude2 here first.'
    return
}

$target = if ($To) { "acc$To" } elseif ($state.acc -eq 'acc1') { 'acc2' } else { 'acc1' }
"sw: $($state.cwd) : $($state.acc) -> $target  (resume $($state.sessionId.Substring(0,8)))"
Set-Location -LiteralPath $state.cwd
& (Join-Path $PSScriptRoot 'launch.ps1') $target '--resume' $state.sessionId
