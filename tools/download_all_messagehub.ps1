# Downloads ALL English messages (text only) from MessageHub into APP_Books\English,
# so publish_books.bat can put them in the app.
# Safe to stop and run again: messages already in the folder are never downloaded again.
param([string]$Audio = "no", [string]$Lang = "en")
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # much faster downloads
$base = 'https://www.messagehub.info'
# English -> APP_Books\English ; Tamil (MessageHub's translations) -> APP_Books\Tamil_MessageHub
$folderName = if ($Lang -eq 'ta') { 'Tamil_MessageHub' } else { 'English' }
$textDir = Join-Path $env:USERPROFILE ('OneDrive\Desktop\APP_Books\' + $folderName)
$audioDir = Join-Path $env:USERPROFILE 'Documents\MessageHub\Audio'
New-Item -ItemType Directory -Force -Path $textDir | Out-Null
if ($Audio -eq 'yes') { New-Item -ItemType Directory -Force -Path $audioDir | Out-Null }
$log = Join-Path $textDir '_download_log.txt'

function Get-Page($url) {
  try { return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 90).Content } catch { return $null }
}

# 1) Read MessageHub's English Message Index: one table row per sermon
#    (RefNum, title, ... , HTML, Audio). Take sermons whose HTML (text) is available ("A").
Write-Host "Reading the list of messages from MessageHub..."
$codes = New-Object System.Collections.Generic.SortedSet[string]
$html = Get-Page "$base/$Lang/message_index_report.do"
if ($html) {
  foreach ($row in [regex]::Matches($html, '<tr>(.*?)</tr>', 'Singleline')) {
    $cells = @()
    foreach ($td in [regex]::Matches($row.Groups[1].Value, '<td[^>]*>(.*?)</td>', 'Singleline')) {
      $cells += (($td.Groups[1].Value -replace '<[^>]+>', '') -replace '&nbsp;', '').Trim()
    }
    if ($cells.Count -ge 12 -and $cells[10] -eq 'A' -and $cells[0] -match '^\d{2}-\d{4}[A-Za-z]?$') {
      [void]$codes.Add($cells[0].ToUpper())
    }
  }
}
if ($codes.Count -lt 50) {
  Write-Host "Could not read the full list from MessageHub (found only $($codes.Count))."
  Write-Host "Please send a screenshot of this window to Claude."
  exit 1
}
Write-Host "Found $($codes.Count) messages."

# 2) Audio too?
$withAudio = $false
if ($Audio -eq 'ask') {
  Write-Host ""
  Write-Host "Download the audio (MP3) as well?"
  Write-Host "  WARNING: all audio is very large (roughly 40-80 GB) and takes many hours."
  $a = Read-Host "Type Y for audio + text, or N for text only"
  $withAudio = ($a -match '^[Yy]')
} else { $withAudio = ($Audio -eq 'yes') }

# 3) Download, one by one (with a short pause so we are polite to their server).
$i = 0; $okT = 0; $okA = 0; $fail = 0
foreach ($c in $codes) {
  $i++
  $textFile = Join-Path $textDir "$c.messagehub"
  # Already here (any file starting with this code)? Then skip it.
  $have = (Test-Path $textFile) -or (Get-ChildItem -Path $textDir -Filter "$c*.messagehub" -ErrorAction SilentlyContinue)
  if (-not $have) {
    try {
      Invoke-WebRequest -Uri "$base/$Lang/readMessage.msg?ref_num=$c" -UseBasicParsing -OutFile $textFile -TimeoutSec 90
      $okT++
      Write-Host ("[{0}/{1}] text   {2}" -f $i, $codes.Count, $c)
    } catch {
      $fail++; "$c`ttext`t$($_.Exception.Message)" | Add-Content $log
      if (Test-Path $textFile) { Remove-Item $textFile }
      Write-Host ("[{0}/{1}] FAILED text {2}" -f $i, $codes.Count, $c)
    }
    Start-Sleep -Milliseconds 800
  }
  if ($withAudio -and -not (Get-ChildItem -Path $audioDir -Filter "$c *.mp3" -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $audioDir "$c.mp3"))) {
    $page = Get-Page "$base/$Lang/read.do?ref_num=$c"
    $mp3 = if ($page) { [regex]::Match($page, 'href="([^"]+\.mp3)"').Groups[1].Value } else { '' }
    if ($mp3) {
      $title = [regex]::Match($page, "$([regex]::Escape($c))\s*-\s*([^<]+)<").Groups[1].Value.Trim()
      $title = ($title -replace '[\\/:*?"<>|]', ' ').Trim()
      $name = if ($title) { "$c $title.mp3" } else { "$c.mp3" }
      $url = if ($mp3.StartsWith('http')) { $mp3 } else { $base + '/' + $mp3.TrimStart('.', '/') }
      $tmp = Join-Path $audioDir "$c.part"
      try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tmp -TimeoutSec 1800
        Move-Item $tmp (Join-Path $audioDir $name) -Force
        $okA++
        Write-Host ("[{0}/{1}] audio  {2}" -f $i, $codes.Count, $name)
      } catch {
        $fail++; "$c`taudio`t$($_.Exception.Message)" | Add-Content $log
        if (Test-Path $tmp) { Remove-Item $tmp }
        Write-Host ("[{0}/{1}] FAILED audio {2}" -f $i, $codes.Count, $c)
      }
    } else {
      "$c`taudio`tno audio link found" | Add-Content $log
    }
    Start-Sleep -Milliseconds 800
  }
}
Write-Host ""
Write-Host "Done. New text: $okT   New audio: $okA   Failed: $fail"
Write-Host "Saved in: $textDir"
Write-Host "Next: run publish_books.bat to put them in the app."
if ($fail -gt 0) { Write-Host "Failed items are listed in $log. Run this again to retry them." }
