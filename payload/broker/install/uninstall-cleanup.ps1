# Full uninstall cleanup — run by the installer's uninstaller BEFORE it deletes
# the program files. Removes everything EXCEPT the agent browser profile (your
# logins/cookies): stops the broker and the agent browser, reverses the default-
# browser registration, and deletes the broker's runtime data (token/port/config).
$ErrorActionPreference = 'SilentlyContinue'

# 1) Stop the broker (node running broker.js) and the agent browser (a Chromium
#    launched with the agent profile), so their files unlock for removal.
Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -and (
    $_.CommandLine -match 'broker[\\/]src[\\/]broker\.js' -or
    ($_.Name -match '^(chrome|msedge|vivaldi)\.exe$' -and $_.CommandLine -match 'Browser-Agent-for-Integration')
  )
} | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
Start-Sleep -Milliseconds 600

# 2) Reverse the default-browser registration (registry keys, shortcuts, launcher).
try { & (Join-Path $PSScriptRoot 'unregister.ps1') | Out-Null } catch {}

# 3) Remove the broker's runtime data dir (token/port/config). NOT the profile.
Remove-Item -Path (Join-Path $env:LOCALAPPDATA 'BrowserIntegrationBroker') -Recurse -Force

Write-Output 'Uninstall cleanup done (agent browser profile kept).'
