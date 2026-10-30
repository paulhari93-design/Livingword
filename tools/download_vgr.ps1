# Downloads Brother Branham's sermons (English, or -Lang TAM for Tamil) from Voice Of God Recordings (branham.org),
# as listed on https://branham.org/en/MessageAudio (one list per year, 47- to 65-).
#
#   -What text   PDFs  -> APP_Books\English_VGR          (used by the app)
#   -What audio  M4A   -> Documents\VGR\Audio_English    (kept for later, not used yet)
#   -Lang TAM          -> APP_Books\Tamil_VGR and Documents\VGR\Audio_Tamil
#
# Already downloaded files are skipped, so it can be stopped and started again any time.
param([string]$What = "text", [string]$Years = "", [string]$Lang = "ENG")
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$Lang = $Lang.ToUpper()
if ($Lang -eq 'TAM') {
  $textDir  = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books\Tamil_VGR'
  $audioDir = Join-Path $env:USERPROFILE 'Documents\VGR\Audio_Tamil'
  $listFile = Join-Path $env:USERPROFILE 'Documents\VGR\vgr_tamil_list.csv'
} else {
  $textDir  = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books\English_VGR'
  $audioDir = Join-Path $env:USERPROFILE 'Documents\VGR\Audio_English'
  $listFile = Join-Path $env:USERPROFILE 'Documents\VGR\vgr_english_list.csv'
}
$log      = Join-Path $env:USERPROFILE 'Documents\VGR\download_errors.txt'
$dest = if ($What -eq 'audio') { $audioDir } else { $textDir }
New-Item -ItemType Directory -Force -Path $dest, (Split-Path $listFile) | Out-Null

$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
$base = 'https://branham.org'

function Get-Items([string]$html) {
  # One block per sermon: code, title, PDF link, audio link.
  $items = @()
  $blocks = [regex]::Split($html, 'class="messagebox"')
  foreach ($b in $blocks) {
    # English shows "65-1204", other languages "TAM 65-1204". (Books like "TAM BK-AGES" are skipped.)
    $code = [regex]::Match($b, 'class="prodtext">\s*(?:[A-Z]{3}\s+)?([0-9]{2}-[0-9]{4}[A-Za-z]?)\s*<').Groups[1].Value
    if (-not $code) { continue }
    $title = [regex]::Match($b, 'class="prodtexttitle">([^<]*)<').Groups[1].Value.Trim()
    $title = [System.Net.WebUtility]::HtmlDecode($title)
    $pdf = [regex]::Match($b, 'href="([^"]+\.pdf)"').Groups[1].Value
    $m4a = [regex]::Match($b, 'href="([^"]+\.(m4a|mp3))"').Groups[1].Value
    $items += [pscustomobject]@{ Code = $code; Title = $title; Pdf = $pdf; Audio = $m4a }
  }
  return $items
}

# 1) The list of sermons, year by year.
Write-Host "Reading the list of sermons from branham.org ..."
$session = $null
$page = Invoke-WebRequest -Uri "$base/en/MessageAudio" -UseBasicParsing -UserAgent $ua -SessionVariable session -TimeoutSec 120
$form = @()
foreach ($m in [regex]::Matches($page.Content, '<input[^>]*type="hidden"[^>]*>')) {
  $n = [regex]::Match($m.Value, 'name="([^"]*)"').Groups[1].Value
  $v = [regex]::Match($m.Value, 'value="([^"]*)"').Groups[1].Value
  if ($n) { $form += @{ name = $n; value = [System.Net.WebUtility]::HtmlDecode($v) } }
}
$form += @{ name = 'ctl00$sitesearch'; value = '' }
$form += @{ name = 'ctl00$main$criteria'; value = '' }

$all = @{}
function Post-Method([string]$method, $extra) {
  $body = @{ formVars = ($form + $extra) } | ConvertTo-Json -Depth 5 -Compress
  return Invoke-RestMethod -Method Post -Uri "$base/branham/messageaudio.aspx/$method" -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
         -ContentType 'application/json; charset=utf-8' -UserAgent $ua -WebSession $session -TimeoutSec 180
}
if ($Lang -ne 'ENG') {
  # Switch the site to this language, then ask for the whole list.
  try {
    $r = Post-Method 'wmSetLanguage' @(@{ name = 'language'; value = $Lang })
    ($r | ConvertTo-Json -Depth 5) | Set-Content (Join-Path (Split-Path $listFile) "debug_${Lang}_setlang.json") -Encoding UTF8
    Write-Host "  Language: $(([string]$r.d -split '\|')[0] -replace '<[^>]+>', '')"
    $r = Post-Method 'wmSearch' @(@{ name = 'searchcriteria'; value = '' })
    # Keep what the site answered, so it can be checked if nothing is found.
    ($r | ConvertTo-Json -Depth 5) | Set-Content (Join-Path (Split-Path $listFile) "debug_${Lang}_all.json") -Encoding UTF8
    $found = Get-Items ([string]$r.d[0])
    foreach ($it in $found) { $all[$it.Code] = $it }
    Write-Host "  all  $($found.Count) sermons"
  } catch {
    Write-Host "  FAILED: $($_.Exception.Message)"
    "list`t$Lang`t$($_.Exception.Message)" | Add-Content $log
  }
}
# Year by year as well (for English this is the only way; for other languages it fills gaps).
$yearList = if ($Years) { $Years -split ',' } else { 47..65 | ForEach-Object { "$_-" } }
foreach ($y in $yearList) {
  try {
    $r = Post-Method 'wmSearchByYear' @(@{ name = 'year'; value = $y })
    if ($y -eq '63-') { ($r | ConvertTo-Json -Depth 5) | Set-Content (Join-Path (Split-Path $listFile) "debug_${Lang}_63.json") -Encoding UTF8 }
    $found = Get-Items ([string]$r.d[0])
    $added = 0
    foreach ($it in $found) { if (-not $all.ContainsKey($it.Code)) { $added++ }; $all[$it.Code] = $it }
    Write-Host ("  {0}  {1} sermons" -f $y, $found.Count)
  } catch {
    Write-Host "  $y  FAILED: $($_.Exception.Message)"
    "list`t$y`t$($_.Exception.Message)" | Add-Content $log
  }
  Start-Sleep -Milliseconds 500
}
$list = $all.Values | Sort-Object Code
$list | Export-Csv -Path $listFile -NoTypeInformation -Encoding UTF8
Write-Host "Found $($list.Count) sermons. (List saved: $listFile)"
if ($list.Count -eq 0) { Write-Host "Nothing found - please send Claude a screenshot."; exit 1 }

# 2) Download, one by one.
$i = 0; $ok = 0; $skip = 0; $fail = 0
foreach ($it in $list) {
  $i++
  $url = if ($What -eq 'audio') { $it.Audio } else { $it.Pdf }
  if (-not $url) { continue }
  $ext = [IO.Path]::GetExtension(($url -split '\?')[0])
  $safe = ($it.Title -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' ').Trim()
  # Non-English titles are kept in the list file only (Windows window/file names can garble them).
  $name = if ($safe -and $Lang -eq 'ENG') { "$($it.Code) $safe$ext" } else { "$($it.Code)$ext" }
  if (Get-ChildItem -Path $dest -Filter "$($it.Code) *$ext" -ErrorAction SilentlyContinue) { $skip++; continue }
  if (Test-Path (Join-Path $dest "$($it.Code)$ext")) { $skip++; continue }
  $tmp = Join-Path $dest "$($it.Code).part"
  try {
    Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $ua -OutFile $tmp -TimeoutSec 1800
    Move-Item $tmp (Join-Path $dest $name) -Force
    $ok++
    Write-Host ("[{0}/{1}] {2}" -f $i, $list.Count, $name)
  } catch {
    $fail++
    if (Test-Path $tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
    "$What`t$($it.Code)`t$($_.Exception.Message)" | Add-Content $log
    Write-Host ("[{0}/{1}] FAILED {2}" -f $i, $list.Count, $it.Code)
  }
  Start-Sleep -Milliseconds 400
}
Write-Host ""
Write-Host "Done. New: $ok   Already there: $skip   Failed: $fail"
Write-Host "Saved in: $dest"
if ($fail -gt 0) { Write-Host "Failed ones are listed in $log. Run this again to retry them." }
