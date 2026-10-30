# Keeps Windows from going to sleep for a while (default 30 minutes).
# The screen may still turn off or lock; programs keep running.
param([int]$Minutes = 30)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Awake {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
$ES_CONTINUOUS = [uint32]2147483648
$ES_SYSTEM_REQUIRED = [uint32]1
[Awake]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED) | Out-Null
$end = (Get-Date).AddMinutes($Minutes)
Write-Host "The PC will stay awake until $($end.ToString('HH:mm')). Keep this window open."
while ((Get-Date) -lt $end) {
  $left = [math]::Ceiling(($end - (Get-Date)).TotalMinutes)
  Write-Host -NoNewline "`r  $left minute(s) left   "
  Start-Sleep -Seconds 30
}
[Awake]::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null
Write-Host "`nDone. Normal sleep settings are back."
