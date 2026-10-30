# Saves a few branham.org pages so Claude can see how VGR lists its sermons,
# text and audio. Nothing is downloaded in bulk. Output: APP_Books\_check_vgr
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$out = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books\_check_vgr'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
$urls = [ordered]@{
  'messageaudio'   = 'https://branham.org/en/MessageAudio'
  'messagesearch'  = 'https://branham.org/en/MessageSearch'
  'documents'      = 'https://branham.org/en/documents'
  'latest'         = 'https://branham.org/latest-sermons'
  'permission'     = 'https://branham.org/en/permission'
  'resources'      = 'https://branham.org/en/resources'
  'international'  = 'https://branham.org/en/international'
  'ta_messageaudio'= 'https://branham.org/ta/MessageAudio'
}
$report = @()
foreach ($k in $urls.Keys) {
  $u = $urls[$k]
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $ua -TimeoutSec 60 -MaximumRedirection 5
    [IO.File]::WriteAllText((Join-Path $out "$k.html"), $r.Content, [Text.Encoding]::UTF8)
    $report += "$k`t$($r.StatusCode)`t$u`t$($r.BaseResponse.ResponseUri)"
    Write-Host "OK   $k"
  } catch {
    $report += "$k`tFAILED`t$u`t$($_.Exception.Message)"
    Write-Host "FAIL $k  $($_.Exception.Message)"
  }
}
$report | Set-Content (Join-Path $out 'report.txt') -Encoding UTF8
Write-Host ""
Write-Host "Saved in $out . Tell Claude it is done."
