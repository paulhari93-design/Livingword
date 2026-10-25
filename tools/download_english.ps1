$ErrorActionPreference = 'Continue'
$books = Join-Path $env:USERPROFILE 'OneDrive\Desktop\APP_Books'
$out = Join-Path $books 'English'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$codes = Get-ChildItem -Path $books -Filter *.docx | Where-Object { $_.Name -notlike '~$*' } |
  ForEach-Object { if ($_.Name -match '^(\d{2}-\d{4}[A-Za-z]?)') { $matches[1].ToUpper() } } | Sort-Object -Unique
$log = Join-Path $out '_download_log.txt'
"" | Set-Content $log
foreach ($c in $codes) {
  $file = Join-Path $out "$c.messagehub"
  if (Test-Path $file) { Write-Host "  have      $c"; continue }
  $url = "https://www.messagehub.info/en/readMessage.msg?ref_num=$c"
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $file -PassThru -TimeoutSec 60
    $type = $r.Headers['Content-Type']
    $size = (Get-Item $file).Length
    Write-Host ("  OK        {0}  ({1:N0} bytes)" -f $c, $size)
    "$c`t$type`t$size`t$url" | Add-Content $log
  } catch {
    Write-Host "  FAILED    $c  $($_.Exception.Message)"
    "$c`tFAILED`t$($_.Exception.Message)`t$url" | Add-Content $log
    if (Test-Path $file) { Remove-Item $file }
  }
  Start-Sleep -Seconds 2
}
Write-Host ""
Write-Host "Saved in $out"
