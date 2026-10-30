# Saves VGR's sermon series lists (Seals, Church Ages, Hebrews, ...) to Documents\VGR\vgr_series.json
# so the app's "Series" list can be filled in. Reads only the lists, downloads no sermons.
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36'
$base = 'https://branham.org'
$out = Join-Path $env:USERPROFILE 'Documents\VGR\vgr_series.json'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

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

# The series offered on the page: <option value="seals">The Revelation Of The Seven Seals</option>
$sel = [regex]::Match($page.Content, '(?s)id="ddlseries".*?</select>').Value
$series = [ordered]@{}
foreach ($o in [regex]::Matches($sel, '<option value="([^"]+)">([^<]+)</option>')) {
  $series[$o.Groups[1].Value] = [System.Net.WebUtility]::HtmlDecode($o.Groups[2].Value).Trim()
}
Write-Host "Series on branham.org: $($series.Count)"

$result = [ordered]@{}
foreach ($key in $series.Keys) {
  $body = @{ formVars = ($form + @(@{ name = 'series'; value = $key })) } | ConvertTo-Json -Depth 5 -Compress
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$base/branham/messageaudio.aspx/wmSearchBySeries" -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
         -ContentType 'application/json; charset=utf-8' -UserAgent $ua -WebSession $session -TimeoutSec 120
    $html = [string]$r.d[0]
    $items = @()
    foreach ($b in [regex]::Split($html, 'class="messagebox"')) {
      $code = [regex]::Match($b, 'class="prodtext">\s*(?:[A-Z]{3}\s+)?([0-9A-Z]{2,3}-[0-9A-Z]{2,5})\s*<').Groups[1].Value
      if (-not $code) { continue }
      $title = [System.Net.WebUtility]::HtmlDecode([regex]::Match($b, 'class="prodtexttitle">([^<]*)<').Groups[1].Value.Trim())
      $items += [ordered]@{ code = $code; title = $title }
    }
    $result[$key] = [ordered]@{ name = $series[$key]; items = $items }
    Write-Host ("  {0,-12} {1,3}  {2}" -f $key, $items.Count, $series[$key])
  } catch {
    Write-Host "  $key FAILED: $($_.Exception.Message)"
  }
  Start-Sleep -Milliseconds 400
}
($result | ConvertTo-Json -Depth 6) | Set-Content -Path $out -Encoding UTF8
Write-Host ""
Write-Host "Saved: $out . Tell Claude it is done."
