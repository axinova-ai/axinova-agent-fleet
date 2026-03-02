'use strict';

/**
 * !help — list all available commands
 */
async function execute(message) {
  const lines = [
    '**Local Console Bot — Commands**',
    '',
    '`!help` — Show this help message',
    '`!ping` — Bot health check + config summary',
    '`!ping local` — Check Ollama connectivity and latency',
    '`!models` — List model aliases and available Ollama models',
    '`!model <alias>` — Set the default model for this channel (e.g. `!model local-code`)',
    '`!ask <prompt>` — Send a prompt to Ollama and get a response',
    '`!status` — Fleet health dashboard (Ollama, Vikunja, VPN, agents)',
    '',
    '**Notes:**',
    '- Rate limit: 5 `!ask` requests per minute per user',
    '- One `!ask` at a time per channel (others queued with "Busy")',
    '- Responses over 2000 chars are attached as a file',
    '- Default model: `local-general` (qwen2.5:7b-instruct)',
  ];

  await message.reply(lines.join('\n'));
}

module.exports = { name: 'help', execute };
