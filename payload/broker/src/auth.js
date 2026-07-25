'use strict';
// Random bearer token + bound-port discovery files, stored under the user's
// LOCALAPPDATA (user-scoped). NOTE: a same-user process can read these files —
// the token defends against network/web/other-user access, not same-user malware.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { dataDir } = require('./config');

function tokenFile() { return path.join(dataDir(), 'token'); }
function portFile() { return path.join(dataDir(), 'port'); }

// Load the persistent bearer token, or mint one on first run. The token is STABLE
// across broker restarts: it lives in a user-only (ACL'd) file under LOCALAPPDATA and
// is reused for the life of the install. Stability is REQUIRED because a client bakes
// the token it read at startup — chrome-devtools-mcp receives it once via --wsHeaders
// and cannot refresh it. A token that changed per broker lifetime would strand any
// client whose broker had since restarted, surfacing as an HTTP 401 on (re)connect. A
// freshly minted token (first run, or a lost/corrupt file) is persisted by writeToken
// from the 'listening' handler once this broker wins the port bind; a broker that loses
// the race never writes, so it can't clobber the winner's token file.
function loadOrCreateToken() {
  try {
    const t = fs.readFileSync(tokenFile(), 'utf8').trim();
    if (/^[0-9a-f]{64}$/i.test(t)) return t; // reuse the persisted token
  } catch (e) { /* absent/unreadable → mint a fresh one below */ }
  return crypto.randomBytes(32).toString('hex');
}

function readToken() {
  return fs.readFileSync(tokenFile(), 'utf8').trim();
}

// Re-assert the live token to disk (called by the broker that actually bound the
// port). If two brokers raced to create tokens, this makes the winner's token
// authoritative for clients that read it after probing the port.
function writeToken(t) {
  fs.writeFileSync(tokenFile(), t, { mode: 0o600 });
}

function writePort(p) {
  fs.writeFileSync(portFile(), String(p), { mode: 0o600 });
}

function readPort() {
  return parseInt(fs.readFileSync(portFile(), 'utf8').trim(), 10);
}

module.exports = { loadOrCreateToken, readToken, writeToken, writePort, readPort, tokenFile, portFile };
