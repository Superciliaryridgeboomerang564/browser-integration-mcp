'use strict';
// Transport for Chrome launched with --remote-debugging-pipe.
// CDP messages are UTF-8 JSON, each terminated by a NUL byte (\0), carried over
// fd 3 (parent -> Chrome) and fd 4 (Chrome -> parent). No TCP port is opened.
const EventEmitter = require('events');

class PipeCDP extends EventEmitter {
  constructor(writeStream, readStream) {
    super();
    this._write = writeStream; // child.stdio[3] — writable to Chrome
    this._read = readStream;   // child.stdio[4] — readable from Chrome
    this._buf = Buffer.alloc(0);
    this._read.on('data', (d) => this._onData(d));
    this._read.on('close', () => this.emit('close'));
    this._read.on('error', () => {});
    this._write.on('error', () => {});
  }

  _onData(chunk) {
    this._buf = this._buf.length ? Buffer.concat([this._buf, chunk]) : chunk;
    let idx;
    while ((idx = this._buf.indexOf(0)) !== -1) {
      const raw = this._buf.subarray(0, idx).toString('utf8');
      this._buf = this._buf.subarray(idx + 1);
      if (!raw) continue;
      let msg;
      try { msg = JSON.parse(raw); } catch (e) { continue; }
      this.emit('message', msg);
    }
  }

  send(obj) {
    try {
      this._write.write(JSON.stringify(obj));
      this._write.write('\0');
    } catch (e) { /* pipe closing */ }
  }
}

module.exports = { PipeCDP };
