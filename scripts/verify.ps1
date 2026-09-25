$r = $PSScriptRoot; $real = "$env:USERPROFILE\.claude"
function T($p){ if(Test-Path $p){ (Get-Item $p).LastWriteTime.ToString('s') } else { '-' } }
foreach($a in 'acc1','acc2'){
  "== $a"
  "  .claude\.credentials.json : " + (T "$r\$a\.claude\.credentials.json")
  "  .claude\.claude.json      : " + (T "$r\$a\.claude\.claude.json")
  "  home\.claude.json         : " + (T "$r\$a\.claude.json")
  "  projects\ (own)           : " + (T "$r\$a\.claude\projects")
  $f="$r\$a\.claude\.credentials.json"
  if(Test-Path $f){ try{ $j=Get-Content $f -Raw|ConvertFrom-Json; "  sub type: " + $j.claudeAiOauth.subscriptionType }catch{"  (unreadable)"} }
  $oj="$r\$a\.claude\.claude.json"; if(-not(Test-Path $oj)){$oj="$r\$a\.claude.json"}
  if(Test-Path $oj){ try{ $c=Get-Content $oj -Raw|ConvertFrom-Json; $e=$c.oauthAccount.emailAddress; if($e){ "  account: " + $e.Substring(0,2) + '***@' + $e.Split('@')[1] } }catch{} }
}
"== real (must be unchanged)"
"  .credentials.json : " + (T "$real\.credentials.json")
"  settings.json     : " + (T "$real\settings.json")
$a1="$r\acc1\.claude\.credentials.json"; $a2="$r\acc2\.claude\.credentials.json"
if((Test-Path $a1) -and (Test-Path $a2)){ "acc1 vs acc2 credentials identical? " + ((Get-FileHash $a1).Hash -eq (Get-FileHash $a2).Hash) }
