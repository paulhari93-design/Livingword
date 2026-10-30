$ProgressPreference = 'SilentlyContinue'
$out = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books\English\_check'
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach ($u in @('https://www.messagehub.info/ta/message_index_report.do', 'https://www.messagehub.info/ta/messages.do')) {
  $name = ($u -split '/')[-1] -replace '\.do$', ''
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 120
    Set-Content -Path (Join-Path $out "ta_$name.html") -Value $r.Content -Encoding UTF8
    Write-Host "OK      $u  ($($r.Content.Length) chars)"
  } catch { Write-Host "FAILED  $u  $($_.Exception.Message)" }
}
