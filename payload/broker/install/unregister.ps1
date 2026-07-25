# Reverse register.ps1: remove the HKCU browser registration, the Start Menu and
# Desktop shortcuts, and the generated launcher. Leaves nothing behind.
$ErrorActionPreference = 'SilentlyContinue'

Remove-Item -Path 'HKCU:\Software\Classes\BrowserIntegrationURL' -Recurse -Force
Remove-Item -Path 'HKCU:\Software\Clients\StartMenuInternet\BrowserIntegration' -Recurse -Force
Remove-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name 'BrowserIntegration' -Force

Remove-Item -Path (Join-Path ([Environment]::GetFolderPath('Programs')) 'Agent Browser.lnk') -Force
Remove-Item -Path (Join-Path ([Environment]::GetFolderPath('Desktop'))  'Agent Browser.lnk') -Force

$vbs = Join-Path (Split-Path $PSScriptRoot) 'tools\bi-open.vbs'
Remove-Item -Path $vbs -Force

Write-Output 'Unregistered Agent Browser (HKCU keys, shortcuts, launcher removed).'
