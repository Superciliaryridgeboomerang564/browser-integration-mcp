'use strict';
// Broker: owns the shared agent browser. It launches the browser on a private
// CDP pipe (no TCP debug port) and exposes a token-guarded loopback WebSocket
// that speaks the browser-level CDP. The browser is launched only after the WS
// port bind is won, so two racing brokers never open two browsers on one profile.
//
// Access model: single-active "driver" (an MCP client). A newly connecting driver
// SUPERSEDES the previous one and the shared Chrome connection's discovery state is
// reset, so agents take turns on one browser without two concurrent autoAttach
// clients. A transient "opener" (the bi-open URL shim, role X-BI-Role: opener) may
// connect alongside without kicking the driver; the broker restricts it to a single
// browser-level command (Target.createTarget). Per-client request `id`s are remapped
// onto the single pipe; responses route back by id; events broadcast to connected
// clients. Hardening: a bearer token (stable per install, user-only ACL), fail-closed
// peer-process verification, the opener command whitelist, and the data dir locked
// to the current user (see config.hardenDataDir).
const { spawn, execFile } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const { PipeCDP } = require('./pipe-cdp');
const auth = require('./auth');
const config = require('./config');

function log(...a) { process.stderr.write('[broker] ' + a.join(' ') + '\n'); }

// System PowerShell (resolve regardless of PATH) for the peer-process lookup.
const POWERSHELL = path.join(process.env.SystemRoot || process.env.windir || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

const token = auth.loadOrCreateToken(); // stable per-install token (persisted, user-only ACL); see auth.loadOrCreateToken
config.hardenDataDir(); // lock token/port/config to the current user (drops inherited ACEs)
const browser = config.findBrowser();
if (!browser) {
  log('No supported browser found. Set BI_BROKER_BROWSER=<path to chrome/edge/vivaldi>.');
  process.exit(2);
}
const profile = config.profileDir();
const port = config.port();

// We launch the browser ourselves, so we simply never add --enable-automation.
const chromeArgs = [
  '--remote-debugging-pipe',
  `--user-data-dir=${profile}`,
  '--disable-blink-features=AutomationControlled',
  '--no-first-run',
  '--no-default-browser-check',
  '--hide-crash-restore-bubble',
];
// Optional headless launch (tests/CI; a headless browser can't be the default
// link handler, so this is not for normal use).
if (process.env.BI_BROKER_HEADLESS) chromeArgs.push('--headless=new');

// The browser is launched ONLY after we win the port bind (see launchBrowser, called
// from the 'listening' handler). If two brokers cold-start at once, the loser hits
// EADDRINUSE and exits BEFORE launching — so there is never a second Chrome on the
// shared profile.
let child = null;
let chrome = null;

// ---- Multiplexer state ----
let seq = 0;
const pending = new Map(); // globalId -> { ws, origId } | { internal: true }
const clients = new Set(); // Set<WebSocket>

function sendTo(ws, obj) {
  try { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj)); } catch (e) {}
}

// Broker-originated CDP command (its response is swallowed, never sent to clients).
function chromeSend(method, params) {
  const gid = ++seq;
  pending.set(gid, { internal: true });
  chrome.send({ id: gid, method, params: params || {} });
}

// Return Chrome's single pipe connection to a clean discovery state, so the NEXT
// driver's Target.setAutoAttach re-enumerates existing tabs. Without this, autoAttach
// stays enabled on the connection from the previous driver and Chrome treats the new
// driver's setAutoAttach as a no-op (the new driver would see an empty browser).
function resetDiscovery() {
  chromeSend('Target.setAutoAttach', { autoAttach: false, waitForDebuggerOnStart: false, flatten: true });
  chromeSend('Target.setDiscoverTargets', { discover: false });
}

// Launch the shared browser and wire its CDP pipe. Called ONLY after we win the port
// bind, so a broker that lost the race never spawns a second Chrome on the profile.
function launchBrowser() {
  log('launching', browser);
  // Must match how puppeteer launches for --remote-debugging-pipe on Windows:
  // ALL of stdio 0-4 are 'pipe'. Mixing 'inherit'/'ignore' for 0-2 breaks handle
  // inheritance for the fd3/fd4 CDP pipes on Windows (Chrome closes them at once).
  // fd3 = we write to Chrome; fd4 = we read from Chrome.
  child = spawn(browser, chromeArgs, {
    stdio: ['pipe', 'pipe', 'pipe', 'pipe', 'pipe'],
    env: config.browserEnv(), // clean env — see config.browserEnv() for why
    windowsHide: false,
  });
  child.on('error', (e) => { log('failed to launch browser:', e && e.message); process.exit(2); });
  child.on('exit', (code) => { log('browser exited', code); process.exit(0); });

  // Drain Chrome's stdout/stderr so their pipe buffers never fill and block it.
  child.stdout.on('data', () => {});
  child.stderr.on('data', (d) => { if (process.env.BI_BROKER_DEBUG) process.stderr.write(d); });
  child.stdout.on('error', () => {});
  child.stderr.on('error', () => {});

  chrome = new PipeCDP(child.stdio[3], child.stdio[4]);
  chrome.on('close', () => { log('pipe closed'); shutdown(); });
  chrome.on('message', (m) => {
    if (m.id != null && pending.has(m.id)) {
      const p = pending.get(m.id);
      pending.delete(m.id);
      if (p.internal) return; // swallow broker-originated response
      m.id = p.origId;
      sendTo(p.ws, m);
      return;
    }
    // Event or unmatched response: broadcast (single active driver + transient openers).
    for (const ws of clients) sendTo(ws, m);
  });
}

// ---- Peer-process verification -------------------------------------------
// Beyond the token, only accept connections from the processes we expect:
// node.exe running our own scripts (chrome-devtools-mcp / bi-open / i18n). This
// stops naive malware that steals the token and connects from its OWN process.
// It is NOT a hard boundary — a same-user attacker could inject into node.exe or
// overwrite our scripts — but it meaningfully raises the bar. Disable with
// BI_BROKER_VERIFY_PEER=0. It fails CLOSED (rejects) whenever the peer
// can't be confirmed — this check is the ONLY barrier once the token is known, so a
// lookup that returns nothing must not become a free pass. The single fail-open case
// is PowerShell being genuinely unavailable to run the lookup at all (env fault), and
// that bypass is logged loudly by verifyClient.
const OUR_CMD = /chrome-devtools-mcp|bi-open\.js|i18n\.js|broker\.js/i;
function verifyPeer(clientPort, cb) {
  if (process.env.BI_BROKER_VERIFY_PEER === '0') return cb(true, 'disabled');
  if (!clientPort) return cb(false, 'no client port');
  // One PowerShell call: map the client's ephemeral port -> owning PID -> image + cmdline.
  const psScript =
    "$ErrorActionPreference='SilentlyContinue';" +
    "$c=Get-NetTCPConnection -LocalPort " + clientPort + " -RemotePort " + port + " -State Established | Select-Object -First 1;" +
    "if($c){$p=Get-CimInstance Win32_Process -Filter \"ProcessId=$($c.OwningProcess)\";Write-Output ($p.ExecutablePath+'|'+$p.CommandLine)}";
  execFile(POWERSHELL, ['-NoProfile', '-NonInteractive', '-Command', psScript],
    { windowsHide: true, timeout: 6000 }, (err, stdout) => {
      // Only a genuine failure to LAUNCH PowerShell (spawn ENOENT) fails open; a
      // timeout, a non-zero exit, empty output, or a non-matching process all REJECT.
      if (err && err.code === 'ENOENT') return cb(true, 'powershell unavailable (fail-open)');
      if (err) return cb(false, 'peer lookup failed (' + (err.killed ? 'timeout' : (err.code || 'error')) + ')');
      const line = String(stdout || '').trim();
      if (!line) return cb(false, 'peer not identified');
      const sep = line.indexOf('|');
      const exe = (sep >= 0 ? line.slice(0, sep) : line).trim();
      const cmd = sep >= 0 ? line.slice(sep + 1).trim() : '';
      const base = exe.split(/[\\/]/).pop().toLowerCase();
      if (base === 'node.exe' && OUR_CMD.test(cmd)) return cb(true, exe);
      cb(false, (base || '?') + ' :: ' + cmd.slice(0, 100));
    });
}

// An 'opener' (the bi-open URL shim) may issue exactly ONE browser-level command:
// open a tab at an http/https (or about:blank) URL. Enforced here at the broker, so
// the role's limited privilege is a rule — not just a convention a well-behaved
// client happens to follow. (bi-open self-limits too; this makes it non-optional.)
function openerCommandAllowed(m) {
  if (m.method !== 'Target.createTarget') return false;
  const url = m.params && m.params.url;
  if (typeof url !== 'string' || url.length === 0 || url.length > 4096) return false;
  if (/[\x00-\x1F\x7F"]/.test(url)) return false;
  if (url === 'about:blank') return true;
  try {
    const p = new URL(url);
    return p.protocol === 'http:' || p.protocol === 'https:';
  } catch (e) { return false; }
}

// ---- Auth WebSocket server ----
const wss = new WebSocketServer({
  host: '127.0.0.1',
  port,
  // 1) constant-time-ish bearer-token check, then 2) peer-process verification.
  verifyClient: (info, cb) => {
    const header = info.req.headers['authorization'] || '';
    const expected = 'Bearer ' + token;
    let ok = header.length === expected.length;
    try { ok = ok && crypto.timingSafeEqual(Buffer.from(header), Buffer.from(expected)); }
    catch (e) { ok = false; }
    if (!ok) return cb(false, 401, 'Unauthorized');
    verifyPeer(info.req.socket && info.req.socket.remotePort, (allowed, why) => {
      if (allowed) {
        if (/fail-open|disabled/.test(why)) log('WARNING: peer check bypassed (' + why + ')');
        return cb(true);
      }
      log('rejected connection: ' + why);
      cb(false, 403, 'Forbidden');
    });
  },
});

wss.on('listening', () => {
  // We won the port bind, so this broker owns the token/port files (resolves races
  // when several MCP instances try to start a broker at once). Launch the browser
  // now, THEN advertise token+port — so clients only ever connect to a broker that
  // already owns a browser. A broker that LOST the race never reaches here; it exits
  // on the EADDRINUSE 'error' below, having launched no browser.
  launchBrowser();
  auth.writeToken(token);
  auth.writePort(port);
  log(`listening on ws://127.0.0.1:${port}/  (token in ${auth.tokenFile()})`);
});
wss.on('error', (e) => { log('WS server error:', e && e.message); process.exit(3); });

wss.on('connection', (ws, req) => {
  // Roles: a 'driver' is a full CDP client (an MCP). Only ONE driver is active at
  // a time — a newly connecting driver SUPERSEDES the previous one (hand-off), so
  // there are never two concurrent autoAttach clients on the single Chrome pipe.
  // An 'opener' is a transient one-shot client (the URL shim): it never kicks a
  // driver and is never kicked, it just relays its browser-level command.
  const role = String(req.headers['x-bi-role'] || '').toLowerCase() === 'opener' ? 'opener' : 'driver';
  ws.biRole = role;
  if (role === 'driver') {
    for (const c of clients) {
      if (c.biRole === 'driver' && c !== ws) {
        try { c.close(4001, 'superseded by a newer client'); } catch (e) {}
      }
    }
    // Clean the shared Chrome connection so this driver's setAutoAttach re-enumerates
    // tabs (written before the driver's own messages — the pipe is FIFO/ordered).
    resetDiscovery();
  }
  clients.add(ws);
  log(`${role} connected (${clients.size} total)`);
  ws.on('message', (data) => {
    let m;
    try { m = JSON.parse(data.toString('utf8')); } catch (e) { return; }
    if (!m || typeof m !== 'object') return;
    // Openers get only their one allowed command; anything else is dropped (and a
    // JSON-RPC/CDP error is returned if it carried an id) instead of reaching Chrome.
    if (ws.biRole === 'opener' && !openerCommandAllowed(m)) {
      log('opener: rejected ' + (m.method || '?'));
      if (m.id != null) sendTo(ws, { id: m.id, error: { code: -32601, message: 'opener may only call Target.createTarget with an http(s) URL' } });
      return;
    }
    if (m.id != null) {
      const gid = ++seq;
      pending.set(gid, { ws, origId: m.id });
      m.id = gid;
    }
    chrome.send(m);
  });
  ws.on('close', () => {
    clients.delete(ws);
    for (const [gid, p] of pending) if (p.ws === ws) pending.delete(gid);
    log('client disconnected (' + clients.size + ')');
  });
  ws.on('error', () => {});
});

function shutdown() {
  try { if (child) child.kill(); } catch (e) {}
  try { wss.close(); } catch (e) {}
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
