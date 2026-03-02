'use strict';

const { execFile } = require('node:child_process');
const ollama = require('../lib/ollama');

function exec(cmd, args, timeoutMs = 5000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: timeoutMs }, (err, stdout) => {
      if (err) resolve({ ok: false, output: err.message });
      else resolve({ ok: true, output: stdout.trim() });
    });
  });
}

/**
 * !status — fleet health dashboard
 */
async function execute(message) {
  await message.channel.sendTyping();

  const checks = await Promise.all([
    // Ollama
    ollama.health().then((h) => ({
      name: 'Ollama',
      ok: h.ok,
      detail: h.ok ? `${h.latencyMs}ms` : h.error || 'unreachable',
    })),

    // Vikunja tunnel
    (async () => {
      try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 5000);
        const res = await fetch('http://localhost:3456/api/v1/info', {
          signal: controller.signal,
        });
        clearTimeout(timer);
        return {
          name: 'Vikunja',
          ok: res.ok,
          detail: res.ok ? 'tunnel active' : `HTTP ${res.status}`,
        };
      } catch (err) {
        return { name: 'Vikunja', ok: false, detail: 'tunnel down' };
      }
    })(),

    // VPN
    exec('ping', ['-c', '1', '-W', '2', '10.66.66.1']).then((r) => ({
      name: 'VPN',
      ok: r.ok,
      detail: r.ok ? 'connected' : 'unreachable',
    })),

    // Agent daemons
    exec('launchctl', ['list']).then((r) => {
      if (!r.ok) return { name: 'Agents', ok: false, detail: 'launchctl failed' };
      const lines = r.output.split('\n').filter((l) => l.includes('com.axinova.agent-'));
      const running = lines.filter((l) => !l.startsWith('-')).length;
      const total = lines.length;
      return {
        name: 'Agents',
        ok: running > 0,
        detail: `${running}/${total} running`,
      };
    }),

    // OpenClaw
    exec('launchctl', ['list']).then((r) => {
      if (!r.ok) return { name: 'OpenClaw', ok: false, detail: 'unknown' };
      const line = r.output.split('\n').find((l) => l.includes('com.axinova.openclaw'));
      if (!line) return { name: 'OpenClaw', ok: false, detail: 'not loaded' };
      return {
        name: 'OpenClaw',
        ok: !line.startsWith('-'),
        detail: line.startsWith('-') ? 'not running' : 'running',
      };
    }),
  ]);

  const lines = ['**Fleet Status**', '```'];
  for (const c of checks) {
    const icon = c.ok ? 'OK  ' : 'FAIL';
    lines.push(`  ${icon}  ${c.name.padEnd(10)} ${c.detail}`);
  }
  lines.push('```');

  await message.reply(lines.join('\n'));
}

module.exports = { name: 'status', execute };
