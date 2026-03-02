'use strict';

const { AttachmentBuilder } = require('discord.js');
const ollama = require('../lib/ollama');
const routing = require('../lib/routing');
const log = require('../lib/logger');

// Single-flight: one concurrent !ask per channel
const inflight = new Set();

// Rate limiting: 5 requests per 60s per user
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 60_000;
const userRequests = new Map(); // userId → [timestamp, ...]

function checkRateLimit(userId) {
  const now = Date.now();
  let timestamps = userRequests.get(userId) || [];
  timestamps = timestamps.filter((t) => now - t < RATE_WINDOW_MS);
  if (timestamps.length >= RATE_LIMIT) {
    const waitSec = Math.ceil(
      (RATE_WINDOW_MS - (now - timestamps[0])) / 1000
    );
    return { allowed: false, waitSec };
  }
  timestamps.push(now);
  userRequests.set(userId, timestamps);
  return { allowed: true };
}

/**
 * !ask <prompt> — send prompt to Ollama, reply in Discord
 */
async function execute(message, args) {
  const prompt = args.join(' ').trim();
  if (!prompt) {
    await message.reply('Usage: `!ask <prompt>`');
    return;
  }

  // Rate limit
  const rl = checkRateLimit(message.author.id);
  if (!rl.allowed) {
    await message.reply(
      `Rate limited — try again in ${rl.waitSec}s (${RATE_LIMIT} requests per minute).`
    );
    return;
  }

  // Single-flight
  if (inflight.has(message.channelId)) {
    await message.reply(
      'Busy — another `!ask` is running in this channel. Please wait.'
    );
    return;
  }

  inflight.add(message.channelId);
  let typingInterval;

  try {
    const { alias, model } = routing.resolveModel(
      message.channelId,
      message.author.id
    );

    // Send typing indicator and refresh every 8s (Discord expires at ~10s)
    await message.channel.sendTyping();
    typingInterval = setInterval(() => {
      message.channel.sendTyping().catch(() => {});
    }, 8_000);

    log.info('ask:start', {
      user: message.author.tag,
      channel: message.channelId,
      alias,
      model,
      promptLen: prompt.length,
    });

    const start = Date.now();
    const result = await ollama.generate(model, prompt);
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);

    log.info('ask:done', {
      user: message.author.tag,
      model,
      elapsed,
      responseLen: result.response.length,
      evalCount: result.evalCount,
    });

    const footer = `\n\n_${alias} (${model}) — ${elapsed}s_`;
    const text = result.response + footer;

    if (text.length <= 2000) {
      await message.reply(text);
    } else {
      // Attach as file for long responses
      const buf = Buffer.from(result.response, 'utf8');
      const file = new AttachmentBuilder(buf, { name: 'response.txt' });
      await message.reply({
        content: `Response too long (${result.response.length} chars) — attached as file. _${alias} (${model}) — ${elapsed}s_`,
        files: [file],
      });
    }
  } catch (err) {
    log.error('ask:error', { error: err.message });

    if (err.name === 'AbortError') {
      await message.reply('Request timed out (120s). Ollama may be overloaded.');
    } else {
      await message.reply(`Error: ${err.message.slice(0, 200)}`);
    }
  } finally {
    clearInterval(typingInterval);
    inflight.delete(message.channelId);
  }
}

module.exports = { name: 'ask', execute };
