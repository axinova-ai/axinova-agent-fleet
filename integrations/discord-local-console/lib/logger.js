'use strict';

const fs = require('node:fs');
const path = require('node:path');

const LOG_DIR = path.join(
  process.env.HOME || '/tmp',
  '.config',
  'axinova',
  'logs'
);

let logStream = null;

function ensureLogDir() {
  if (!logStream) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const logPath = path.join(LOG_DIR, 'local-console.log');
    logStream = fs.createWriteStream(logPath, { flags: 'a' });
  }
}

function write(level, msg, extra) {
  const entry = {
    ts: new Date().toISOString(),
    level,
    msg,
    ...extra,
  };
  const line = JSON.stringify(entry);

  // Always write to stdout (captured by launchd)
  process.stdout.write(line + '\n');

  // Also append to rotating log file
  try {
    ensureLogDir();
    logStream.write(line + '\n');
  } catch {
    // Best-effort file logging
  }
}

module.exports = {
  info: (msg, extra) => write('info', msg, extra),
  warn: (msg, extra) => write('warn', msg, extra),
  error: (msg, extra) => write('error', msg, extra),
};
