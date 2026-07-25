param(
  [ValidateSet('precheck','install')][string]$Mode = 'precheck',
  [string]$McpDir,
  [string]$ProfileDir,
  [string]$BrowserExe,
  [string]$BrowserName,
  [string]$ResultFile,
  [string]$BrowsersFile
)
$ErrorActionPreference = 'Stop'

function Find-Node {
  $c = Get-Command node -ErrorAction SilentlyContinue
  if ($c -and $c.Source -and (Test-Path $c.Source)) { return $c.Source }
  foreach ($p in @("$env:ProgramFiles\nodejs\node.exe","$env:LOCALAPPDATA\Programs\nodejs\node.exe","${env:ProgramFiles(x86)}\nodejs\node.exe")) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}

# Supported browsers: Chrome, Edge, Vivaldi (all Chromium; same CDP flags).
function Find-Browsers {
  $defs = @(
    @{ Name='Chrome';  Exe='chrome.exe';  Paths=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") },
    @{ Name='Edge';    Exe='msedge.exe';  Paths=@("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe","$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") },
    @{ Name='Vivaldi'; Exe='vivaldi.exe'; Paths=@("$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe","$env:ProgramFiles\Vivaldi\Application\vivaldi.exe","${env:ProgramFiles(x86)}\Vivaldi\Application\vivaldi.exe") }
  )
  $found = @()
  foreach ($d in $defs) {
    $path = $null
    foreach ($root in @('HKCU:','HKLM:')) {
      $ap = "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$($d.Exe)"
      try { $v = (Get-ItemProperty -Path $ap -ErrorAction Stop).'(default)'; if ($v) { $vv = $v.Trim('"'); if (Test-Path $vv) { $path = $vv; break } } } catch {}
    }
    if (-not $path) {
      foreach ($p in $d.Paths) { if ($p -and (Test-Path $p)) { $path = $p; break } }
    }
    if ($path) { $found += @{ Name=$d.Name; Exe=(Resolve-Path $path).Path } }
  }
  return ,$found
}

# UTF-8 with BOM: Inno Setup's LoadStringsFromFile honours the BOM, so Cyrillic
# in paths (e.g. a Russian user name) survives the round-trip intact.
function Write-Utf8Bom($file, $lines) {
  [System.IO.File]::WriteAllLines($file, $lines, (New-Object System.Text.UTF8Encoding($true)))
}

# Remove artifacts left by older (attach-mode) installs: the browser registration
# under HKCU and the three desktop shortcuts, which launched the browser with a
# TCP debugging port. Safe to run even on a first install.
function Remove-LegacyArtifacts {
  foreach ($k in @('HKCU:\Software\Classes\BrowserIntegrationHTM','HKCU:\Software\Clients\StartMenuInternet\BrowserIntegration')) {
    try { if (Test-Path $k) { Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
  }
  try { Remove-ItemProperty -Path 'HKCU:\Software\RegisteredApplications' -Name 'BrowserIntegration' -Force -ErrorAction SilentlyContinue } catch {}
  try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    foreach ($n in @('Browser-Integration (1).lnk','Browser-Integration (2).lnk','Browser-Integration (3).lnk')) {
      $lp = Join-Path $desktop $n
      if (Test-Path $lp) { Remove-Item -Path $lp -Force -ErrorAction SilentlyContinue }
    }
  } catch {}
}

# ---------------- PRECHECK ----------------
if ($Mode -eq 'precheck') {
  $node = Find-Node
  if (-not $node) { if ($BrowsersFile) { Write-Utf8Bom $BrowsersFile @() }; exit 1 }
  $browsers = Find-Browsers
  if (-not $browsers -or $browsers.Count -eq 0) { if ($BrowsersFile) { Write-Utf8Bom $BrowsersFile @() }; exit 2 }
  if ($BrowsersFile) {
    $bl = @()
    foreach ($b in $browsers) { $bl += ($b.Name + '|' + $b.Exe) }
    Write-Utf8Bom $BrowsersFile $bl
  }
  exit 0
}

# ---------------- INSTALL ----------------
$node = Find-Node
if (-not $node) { exit 3 }
$browser = $BrowserExe
if (-not $browser -or -not (Test-Path $browser)) { exit 3 }

# 1) Bake i18n.js. Placeholders are single-quoted JS string literals ('__NODE__',
#    '__BROWSER__', '__PROFILE__'); we replace the quoted token with a JSON string
#    literal via ConvertTo-Json, which escapes backslashes, quotes, and non-ASCII
#    correctly - so paths with Cyrillic, apostrophes, or '$' can never break the file.
$i18 = Join-Path $McpDir 'i18n.js'
$txt = [System.IO.File]::ReadAllText($i18)
$txt = $txt.Replace("'__NODE__'",    ($node    | ConvertTo-Json))
$txt = $txt.Replace("'__BROWSER__'", ($browser | ConvertTo-Json))
$txt = $txt.Replace("'__PROFILE__'", ($ProfileDir | ConvertTo-Json))
[System.IO.File]::WriteAllText($i18, $txt, (New-Object System.Text.UTF8Encoding($false)))
$mcpBaked = -not ($txt -match "'__NODE__'|'__BROWSER__'|'__PROFILE__'")

# 2) Ensure the profile folder exists. At runtime the broker launches the browser
#    against this profile and (via puppeteer) initializes it on first run; here we
#    only guarantee the directory is present and writable.
if (-not (Test-Path $ProfileDir)) {
  try { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null } catch {}
}
$profOk = Test-Path $ProfileDir

# 2b) Persist the broker config (browser + profile) so every entry point - the MCP
#     and the bi-open link shim - drives the SAME browser and profile, even on the
#     very first link click before the MCP has run once.
try {
  $brokerData = Join-Path $env:LOCALAPPDATA 'BrowserIntegrationBroker'
  if (-not (Test-Path $brokerData)) { New-Item -ItemType Directory -Path $brokerData -Force | Out-Null }
  $cfg = @{ browser = $browser; profile = $ProfileDir } | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText((Join-Path $brokerData 'config.json'), $cfg, (New-Object System.Text.UTF8Encoding($false)))
} catch {}

# 3) Clean up artifacts from any previous attach-mode install (registry + shortcuts).
Remove-LegacyArtifacts

# 4) Self-check + machine-readable result (UTF-8 with BOM for Cyrillic paths)
$lines = @()
$lines += "NODE=$node"
$lines += "BROWSER=$browser"
$lines += "BROWSER_NAME=$BrowserName"
$lines += ("MCP_BAKED=" + ([int][bool]$mcpBaked))
$lines += ("PROFILE_OK=" + ([int][bool]$profOk))
$lines += ("MCP_DIR=" + $McpDir)
if ($ResultFile) { Write-Utf8Bom $ResultFile $lines }
$lines | ForEach-Object { Write-Output $_ }

if ($mcpBaked -and $profOk) { exit 0 } else { exit 4 }
