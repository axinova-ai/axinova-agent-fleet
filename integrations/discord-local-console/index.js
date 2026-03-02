'use strict';

const { Client, GatewayIntentBits, Partials } = require('discord.js');
const log = require('./lib/logger');
const routing = require('./lib/routing');

// Command modules
const helpCmd = require('./commands/help');
const pingCmd = require('./commands/ping');
const modelsCmd = require('./commands/models');
const askCmd = require('./commands/ask');
const statusCmd = require('./commands/status');

const PREFIX = '!';

const COMMANDS = {
  help: helpCmd,
  ping: pingCmd,
  models: modelsCmd,
  model: modelsCmd, // alias — handled inside models.js via _commandName
  ask: askCmd,
  status: statusCmd,
};

// --- Validation ---
const token = process.env.DISCORD_TOKEN;
if (!token) {
  log.error('DISCORD_TOKEN not set. Exiting.');
  process.exit(1);
}

// --- Discord client ---
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.DirectMessages,
    GatewayIntentBits.MessageContent,
  ],
  partials: [Partials.Message, Partials.Channel],
});

client.once('ready', () => {
  log.info('Bot online', {
    user: client.user.tag,
    guilds: client.guilds.cache.size,
  });
  routing.load();
});

client.on('messageCreate', async (message) => {
  // Ignore bots and messages without prefix
  if (message.author.bot) return;
  if (!message.content.startsWith(PREFIX)) return;

  const body = message.content.slice(PREFIX.length).trim();
  const [commandName, ...args] = body.split(/\s+/);
  const cmd = COMMANDS[commandName?.toLowerCase()];

  if (!cmd) return; // Unknown command — silently ignore

  // Attach command name for commands that share a handler (model/models)
  message._commandName = commandName.toLowerCase();

  try {
    await cmd.execute(message, args);
  } catch (err) {
    log.error('command:error', { command: commandName, error: err.message });
    try {
      await message.reply(`Internal error: ${err.message.slice(0, 150)}`);
    } catch {
      // Can't reply — channel deleted, perms revoked, etc.
    }
  }
});

// --- Graceful shutdown ---
function shutdown(signal) {
  log.info('Shutting down', { signal });
  client.destroy();
  process.exit(0);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// --- Start ---
client.login(token).catch((err) => {
  log.error('Login failed', { error: err.message });
  process.exit(1);
});
