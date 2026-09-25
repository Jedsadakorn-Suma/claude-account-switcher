# usage.ps1 : show both accounts' rate-limit usage side by side.
#
# Reads state\usage-acc1.json / usage-acc2.json, which shared\statusline.sh writes as a
# side effect of the normal Claude Code statusline (piggybacks on data Claude Code already
# computes each turn -- no separate API call, no token ever read here).
#
# Caveat: a number only updates when that account had a turn recently. An account that
# hasn't been used in a while shows its last-known numbers, marked stale.
param([int]$StaleMinutes = 20)

$u8 = [Text.Encoding]::UTF8
$root = $PSScriptRoot

function Show-One([string]$acc) {
    $file = Join-Path $root "state\usage-$acc.json"
    if (-not (Test-Path -LiteralPath $file)) {
        "{0,-5}  no data yet -- open a claude session under this account first" -f $acc
        return
    }
    try { $o = [IO.File]::ReadAllText($file, $u8) | ConvertFrom-Json } catch {
        "{0,-5}  (unreadable usage file)" -f $acc
        return
    }
    $age = (Get-Date) - [datetime]$o.updatedAt
    $staleTag = if ($age.TotalMinutes -gt $StaleMinutes) { " [stale, {0}m old]" -f [int]$age.TotalMinutes } else { "" }
    $fh = if ($null -ne $o.fiveHourPct) { "{0}% {1}" -f $o.fiveHourPct, $o.fiveHourReset } else { "n/a" }
    $sd = if ($null -ne $o.sevenDayPct) { "{0}% {1}" -f $o.sevenDayPct, $o.sevenDayReset } else { "n/a" }
    "{0,-5}  5h: {1,-28}  7d: {2,-32}{3}" -f $acc, $fh, $sd, $staleTag
}

"Claude usage -- both sandbox accounts (from statusline piggyback, not a live API call)"
Show-One 'acc1'
Show-One 'acc2'
