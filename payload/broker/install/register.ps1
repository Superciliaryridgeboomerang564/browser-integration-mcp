# Register the agent browser as a default-browser CANDIDATE (HKCU) and drop
# Start Menu + Desktop shortcuts. Windows 10/11 will NOT let anything set the
# default programmatically, so this only makes "Agent Browser" selectable — the
# user then picks it in Settings > Default apps (pass -OpenSettings to jump there).
#
# Everything is user-scoped and fully reversible via unregister.ps1.
param(
  [switch]$OpenSettings,
  [string]$BrowserExe   # optional: used as the shortcut icon (else read from config.json)
)
$ErrorActionPreference = 'Stop'

$brokerDir = Split-Path $PSScriptRoot            # ...\broker
$tools     = Join-Path $brokerDir 'tools'
$biOpenJs  = Join-Path $tools 'bi-open.js'
$vbs       = Join-Path $tools 'bi-open.vbs'
if (-not (Test-Path $biOpenJs)) { throw "bi-open.js not found at $biOpenJs" }

# Resolve node.exe (GUI-launched handlers may not have it on PATH).
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
  foreach ($p in @("$env:ProgramFiles\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe")) {
    if (Test-Path $p) { $node = $p; break }
  }
}
if (-not $node) { throw 'Node.js not found. Install Node.js and re-run.' }

# Hidden launcher: wscript runs node with window style 0 (no console flash). The
# (untrusted) URL is passed via the BI_OPEN_URL env var, NOT on the command line,
# so a crafted link cannot inject into the shell command. Chr(34) is a double-quote.
$vbsContent = @"
Set sh = CreateObject("WScript.Shell")
Q = Chr(34)
u = ""
If WScript.Arguments.Count > 0 Then u = WScript.Arguments(0)
sh.Environment("Process")("BI_OPEN_URL") = u
sh.Run Q & "$node" & Q & " " & Q & "$biOpenJs" & Q, 0, False
"@
Set-Content -Path $vbs -Value $vbsContent -Encoding ASCII

$openCmd = "wscript.exe ""$vbs"" ""%1"""
$homeCmd = "wscript.exe ""$vbs"" ""about:blank"""
$progId  = 'BrowserIntegrationURL'

# 1) ProgID with an open-command for URLs.
New-Item -Path "HKCU:\Software\Classes\$progId\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\$progId" -Name '(default)' -Value 'Agent Browser (Browser-Integration)'
Set-ItemProperty -Path "HKCU:\Software\Classes\$progId\shell\open\command" -Name '(default)' -Value $openCmd

# 2) StartMenuInternet registration + Capabilities/URLAssociations.
$smi = 'HKCU:\Software\Clients\StartMenuInternet\BrowserIntegration'
New-Item -Path "$smi\Capabilities\URLAssociations" -Force | Out-Null
New-Item -Path "$smi\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path $smi -Name '(default)' -Value 'Agent Browser'
Set-ItemProperty -Path "$smi\Capabilities" -Name 'ApplicationName' -Value 'Agent Browser'
Set-ItemProperty -Path "$smi\Capabilities" -Name 'ApplicationDescription' -Value 'Opens links in the Browser-Integration agent browser.'
Set-ItemProperty -Path "$smi\Capabilities\URLAssociations" -Name 'http'  -Value $progId
Set-ItemProperty -Path "$smi\Capabilities\URLAssociations" -Name 'https' -Value $progId
Set-ItemProperty -Path "$smi\shell\open\command" -Name '(default)' -Value $homeCmd

# 3) Point RegisteredApplications at the Capabilities so Windows lists the app.
New-Item -Path 'HKCU:\Software\RegisteredApplications' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name 'BrowserIntegration' -Value 'Software\Clients\StartMenuInternet\BrowserIntegration\Capabilities'

# 4) Shortcuts (Start Menu + Desktop) that open the agent browser.
$icon = $null
if ($BrowserExe -and (Test-Path $BrowserExe)) { $icon = $BrowserExe }
else { try { $b = (Get-Content (Join-Path $env:LOCALAPPDATA 'BrowserIntegrationBroker\config.json') -Raw | ConvertFrom-Json).browser; if ($b -and (Test-Path $b)) { $icon = $b } } catch {} }

$wsh = New-Object -ComObject WScript.Shell
function New-AgentShortcut($lnkPath) {
  $sc = $wsh.CreateShortcut($lnkPath)
  $sc.TargetPath  = 'wscript.exe'
  $sc.Arguments   = """$vbs"" ""about:blank"""
  $sc.Description  = 'Open the Browser-Integration agent browser'
  if ($icon) { $sc.IconLocation = "$icon,0" }
  $sc.Save()
}
New-AgentShortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Agent Browser.lnk')
New-AgentShortcut (Join-Path ([Environment]::GetFolderPath('Desktop'))  'Agent Browser.lnk')

Write-Output "Registered 'Agent Browser' (HKCU); shortcuts on Start Menu + Desktop."
Write-Output "To make it the default: Settings > Default apps > Agent Browser (Windows requires manual confirmation)."
if ($OpenSettings) { Start-Process 'ms-settings:defaultapps' }
