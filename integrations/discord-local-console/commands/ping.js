'use strict';

const ollama = require('../lib/ollama');
const routing = require('../lib/routing');

/**
 * !ping       — bot health + config summary
 * !ping local — Ollama health check with latency
 */
async function execute(message, args) {
  if (args[0] === 'local') {
    const h = await ollama.health();
    if (h.ok) {
      await message.reply(`Ollama OK — ${h.latencyMs}ms (${ollama.BASE_URL})`);
    } else {
      await message.reply(
        `Ollama FAIL — ${h.error || 'unreachable'} (${ollama.BASE_URL})`
      );
    }
    return;
  }

  const aliases = routing.getAliasMap();
  const aliasLines = Object.entries(aliases)
    .map(([k, v]) => `  ${k} → ${v}`)
    .join('\n');

  await message.reply(
    [
      '**Local Console Bot** — Online',
      `Ollama: \`${ollama.BASE_URL}\``,
      `Model aliases:\n\`\`\`\n${aliasLines}\n\`\`\``,
      'Use `!ping local` to check Ollama connectivity.',
    ].join('\n')
  );
}

module.exports = { name: 'ping', execute };
