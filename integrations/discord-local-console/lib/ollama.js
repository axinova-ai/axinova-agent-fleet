'use strict';

const log = require('./logger');

const BASE_URL = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
const TIMEOUT_MS = 120_000;

/**
 * Generate a completion from Ollama.
 * Returns { response, model, totalDuration, evalCount }.
 */
async function generate(model, prompt) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(`${BASE_URL}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, stream: false }),
      signal: controller.signal,
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Ollama ${res.status}: ${body.slice(0, 200)}`);
    }

    const data = await res.json();
    return {
      response: data.response || '',
      model: data.model,
      totalDuration: data.total_duration,
      evalCount: data.eval_count,
    };
  } finally {
    clearTimeout(timer);
  }
}

/** List available models. Returns array of { name, size, modifiedAt }. */
async function listModels() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);

  try {
    const res = await fetch(`${BASE_URL}/api/tags`, {
      signal: controller.signal,
    });
    if (!res.ok) throw new Error(`Ollama ${res.status}`);
    const data = await res.json();
    return (data.models || []).map((m) => ({
      name: m.name,
      size: m.size,
      modifiedAt: m.modified_at,
    }));
  } finally {
    clearTimeout(timer);
  }
}

/** Health check — returns { ok, latencyMs } */
async function health() {
  const start = Date.now();
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5_000);
    const res = await fetch(`${BASE_URL}/api/tags`, {
      signal: controller.signal,
    });
    clearTimeout(timer);
    return { ok: res.ok, latencyMs: Date.now() - start };
  } catch (err) {
    return { ok: false, latencyMs: Date.now() - start, error: err.message };
  }
}

module.exports = { generate, listModels, health, BASE_URL };
