$ProgressPreference = 'SilentlyContinue'
$out = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books\English\_check'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$pages = @{
  'index_report' = 'https://www.messagehub.info/en/message_index_report.do';
  'index'        = 'https://www.messagehub.info/en/message_index.do';
  'messages'     = 'https://www.messagehub.info/en/messages.do';
  'home'         = 'https://www.messagehub.info/home.do?show_en=true';
  'read'         = 'https://www.messagehub.info/en/read.do?ref_num=53-0216'
}
foreach ($k in $pages.Keys) {
  try {
    $r = Invoke-WebRequest -Uri $pages[$k] -UseBasicParsing -TimeoutSec 90
    Set-Content -Path (Join-Path $out "$k.html") -Value $r.Content -Encoding UTF8
    Write-Host "OK      $k  ($($r.StatusCode), $($r.Content.Length) chars)"
  } catch {
    Write-Host "FAILED  $k  $($_.Exception.Message)"
    Set-Content -Path (Join-Path $out "$k.error.txt") -Value $_.Exception.Message
  }
}
Write-Host "Saved in $out"
