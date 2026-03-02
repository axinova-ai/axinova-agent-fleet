'use strict';

const routing = require('../lib/routing');
const ollama = require('../lib/ollama');

/**
 * !models          — list aliases + Ollama models
 * !model <alias>   — set channel default model
 */
async function execute(message, args) {
  // !model <alias> — set channel default
  if (args.length > 0 && message._commandName === 'model') {
    const alias = args[0];
    const model = routing.resolveAlias(alias);
    if (!model) {
      const known = Object.keys(routing.getAliasMap()).join(', ');
      await message.reply(`Unknown alias \`${alias}\`. Known: ${known}`);
      return;
    }
    routing.setChannelDefault(message.channelId, alias);
    await message.reply(
      `Channel default set to **${alias}** → \`${model}\``
    );
    return;
  }

  // !models — list all
  const aliases = routing.getAliasMap();
  const { alias: currentAlias } = routing.resolveModel(
    message.channelId,
    message.author.id
  );

  let lines = ['**Model Aliases**'];
  for (const [name, model] of Object.entries(aliases)) {
    const marker = name === currentAlias ? ' ← current' : '';
    lines.push(`  \`${name}\` → \`${model}\`${marker}`);
  }

  // Also show raw Ollama models
  try {
    const models = await ollama.listModels();
    if (models.length > 0) {
      lines.push('', '**Ollama Models**');
      for (const m of models) {
        const sizeMB = Math.round(m.size / 1024 / 1024);
        lines.push(`  \`${m.name}\` (${sizeMB} MB)`);
      }
    }
  } catch {
    lines.push('', '_Could not fetch Ollama models_');
  }

  await message.reply(lines.join('\n'));
}

module.exports = { name: 'models', execute };
