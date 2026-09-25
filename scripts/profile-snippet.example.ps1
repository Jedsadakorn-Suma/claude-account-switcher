# Add to your PowerShell $PROFILE (find it with: $PROFILE), replacing <SANDBOX_ROOT>
# with the absolute path where you cloned/placed these scripts, e.g. C:\Users\you\claude-sandbox

function claude1 { & '<SANDBOX_ROOT>\launch.ps1' acc1 @args }
function claude2 { & '<SANDBOX_ROOT>\launch.ps1' acc2 @args }
function sw      { & '<SANDBOX_ROOT>\sw.ps1' @args }
function cont    { & '<SANDBOX_ROOT>\cont.ps1' @args }
function hsave   { & '<SANDBOX_ROOT>\handoff-save.ps1' @args }
function usage   { & '<SANDBOX_ROOT>\usage.ps1' @args }
