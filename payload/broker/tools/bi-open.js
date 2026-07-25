#!/usr/bin/env node
'use strict';
// URL-open shim. Registered as the default browser: Windows launches
// `bi-open <url>`, we forward it to the broker as Target.createTarget so the link
// opens as a tab in the shared agent browser. Starts the broker if it isn't up.
// Connects with role 'opener' so it never supersedes the active MCP driver.
const path = require('path');
const net = require('net');
const { spawn } = require('child_process');
const WebSocket = require('ws');
const auth = require('../src/auth');

const BROKER_MAIN = path.join(__dirname, '..', 'src', 'broker.js');

// The URL arrives from the OS default-browser handler (untrusted). Accept it from
// argv OR the BI_OPEN_URL env var (the VBS launcher uses the env var so the URL
// never enters a shell command line), and allow ONLY http/https/about:blank with
// no control characters or quotes — so a crafted link can't inject anything.
function safeUrl(u) {
  if (typeof u !== 'string' || u.length === 0 || u.length > 4096) return null;
  if (/[\x00-\x1F\x7F"]/.test(u)) return null;
  if (u === 'about:blank') return u;
  try {
    const parsed = new URL(u);
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return u;
  } catch (e) { /* not a URL */ }
  return null;
}

const url = safeUrl(process.argv[2] || process.env.BI_OPEN_URL || '');
if (!url) { console.error('bi-open: refused invalid or non-http(s) URL'); process.exit(2); }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function probe(port) {
  return new Promise((resolve) => {
    if (!port) return resolve(false);
    const s = net.connect(port, '127.0.0.1');
    const done = (ok) => { try { s.destroy(); } catch (e) {} resolve(ok); };
    s.on('connect', () => done(true));
    s.on('error', () => done(false));
    s.setTimeout(1000, () => done(false));
  });
}
function readPort() { try { return auth.readPort(); } catch (e) { return 0; } }

async function ensureBroker() {
  if (await probe(readPort())) return;
  try {
    const b = spawn(process.execPath, [BROKER_MAIN], { detached: true, stdio: 'ignore', windowsHide: true });
    b.unref();
  } catch (e) {}
  for (let i = 0; i < 40; i++) { await sleep(500); if (await probe(readPort())) return; }
  throw new Error('broker did not come up');
}

async function main() {
  await ensureBroker();
  const port = auth.readPort();
  const token = auth.readToken();
  const ws = new WebSocket(`ws://127.0.0.1:${port}/`, { headers: { Authorization: 'Bearer ' + token, 'X-BI-Role': 'opener' } });
  const timer = setTimeout(() => { console.error('timeout'); process.exit(4); }, 10000);
  ws.on('open', () => { ws.send(JSON.stringify({ id: 1, method: 'Target.createTarget', params: { url, newWindow: false } })); });
  ws.on('message', (data) => {
    let m; try { m = JSON.parse(data.toString('utf8')); } catch (e) { return; }
    if (m.id === 1) {
      clearTimeout(timer);
      if (m.error) { console.error('error:', JSON.stringify(m.error)); ws.close(); process.exit(1); }
      console.log('opened target', m.result && m.result.targetId);
      ws.close(); process.exit(0);
    }
  });
  ws.on('unexpected-response', (_req, res) => { console.error('auth failed (HTTP ' + res.statusCode + ')'); process.exit(1); });
  ws.on('error', (e) => { console.error('ws error:', e && e.message); process.exit(1); });
}

main().catch((e) => { console.error(e && e.message ? e.message : e); process.exit(3); });
