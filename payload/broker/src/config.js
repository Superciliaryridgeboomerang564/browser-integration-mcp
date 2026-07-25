'use strict';
// Browser discovery, profile dir, and port for the broker.
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const PF = process.env.ProgramFiles || 'C:\\Program Files';
const PF86 = process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)';
const LOCAL = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');

// Supported Chromium browsers (same CDP). Order = preference.
const CANDIDATES = [
  ['Chrome', [
    path.join(PF, 'Google\\Chrome\\Application\\chrome.exe'),
    path.join(PF86, 'Google\\Chrome\\Application\\chrome.exe'),
    path.join(LOCAL, 'Google\\Chrome\\Application\\chrome.exe'),
  ]],
  ['Edge', [
    path.join(PF86, 'Microsoft\\Edge\\Application\\msedge.exe'),
    path.join(PF, 'Microsoft\\Edge\\Application\\msedge.exe'),
  ]],
  ['Vivaldi', [
    path.join(LOCAL, 'Vivaldi\\Application\\vivaldi.exe'),
    path.join(PF, 'Vivaldi\\Application\\vivaldi.exe'),
    path.join(PF86, 'Vivaldi\\Application\\vivaldi.exe'),
  ]],
];

// Persisted choice (browser + profile), written by whoever first configures the
// broker (the MCP installer / i18n) so every entry point — MCP and the bi-open
// shim — drives the SAME browser and profile.
function configFile() { return path.join(dataDir(), 'config.json'); }
function readConfigFile() {
  try { return JSON.parse(fs.readFileSync(configFile(), 'utf8')) || {}; } catch (e) { return {}; }
}

// Precedence: env override > persisted config.json > auto-detect.
function findBrowser() {
  const override = process.env.BI_BROKER_BROWSER;
  if (override && fs.existsSync(override)) return override;
  const cfg = readConfigFile();
  if (cfg.browser && fs.existsSync(cfg.browser)) return cfg.browser;
  for (const [, paths] of CANDIDATES) {
    for (const p of paths) {
      if (p && fs.existsSync(p)) return p;
    }
  }
  return null;
}

// Persistent, dedicated agent profile (logins survive across restarts).
function dataDir() {
  const d = path.join(LOCAL, 'BrowserIntegrationBroker');
  fs.mkdirSync(d, { recursive: true });
  return d;
}

// BI_BROKER_PROFILE lets the caller (e.g. the MCP installer) point the broker at
// an existing agent profile so logins/cookies persist there.
// Precedence: env override > persisted config.json > default under dataDir().
function profileDir() {
  const p = process.env.BI_BROKER_PROFILE || readConfigFile().profile || path.join(dataDir(), 'profile');
  fs.mkdirSync(p, { recursive: true });
  return p;
}

// Fixed default keeps MCP config stable; the actual bound port is also written to
// a file (auth.writePort) so clients can discover it if overridden.
function port() {
  const p = parseInt(process.env.BI_BROKER_PORT || '9333', 10);
  return Number.isFinite(p) ? p : 9333;
}

// Curated, minimal environment for the browser child. Inheriting the FULL parent
// env makes Chromium (Edge especially) forward the launch to a background/startup
// process and immediately exit — which kills the --remote-debugging-pipe before it
// is usable. Passing only the standard Windows variables a browser needs avoids
// that (same effect as @puppeteer/browsers launching with a clean env).
const ENV_ALLOW = [
  'SystemRoot', 'windir', 'SystemDrive', 'ComSpec', 'PATH', 'PATHEXT',
  'TEMP', 'TMP', 'LOCALAPPDATA', 'APPDATA', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH',
  'PUBLIC', 'ALLUSERSPROFILE', 'ProgramData',
  'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432',
  'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432',
  'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'OS',
  'COMPUTERNAME', 'USERNAME', 'USERDOMAIN', 'SESSIONNAME',
];

function browserEnv() {
  const src = process.env;
  const out = {};
  for (const k of ENV_ALLOW) if (src[k] !== undefined) out[k] = src[k];
  return out;
}

// Restrict the broker data dir (token/port/config) to the current user and drop
// inherited ACEs (removes the AppContainer package SID + other users, so sandboxed
// / low-integrity processes can't read the token). This does NOT stop a process
// running as the SAME user (an OS limitation, not fixable by ACLs).
// Best-effort and idempotent; safe to call on every startup.
//
// The directory gets inheritable (OI)(CI) Full so NEW files (token/port/config)
// are user-only automatically. Leaf FILES must use plain (F) — the (OI)(CI)
// inheritance flags on a file produce an ACE that grants no effective access
// (that bug once locked the owner out of the token file).
function hardenDataDir() {
  try {
    const dir = dataDir();
    const user = (process.env.USERDOMAIN ? process.env.USERDOMAIN + '\\' : '') + (process.env.USERNAME || '');
    if (!user.trim() || user.trim() === '\\') return;
    const icacls = (args) => { try { execFileSync('icacls', args, { stdio: 'ignore', timeout: 8000, windowsHide: true }); } catch (e) {} };
    icacls([dir, '/inheritance:r', '/grant:r', user + ':(OI)(CI)(F)']);
    for (const f of ['token', 'port', 'config.json']) {
      const p = path.join(dir, f);
      if (fs.existsSync(p)) icacls([p, '/inheritance:r', '/grant:r', user + ':(F)']);
    }
  } catch (e) { /* best-effort */ }
}

module.exports = { findBrowser, dataDir, profileDir, port, browserEnv, hardenDataDir };
