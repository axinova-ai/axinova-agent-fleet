'use strict';

const fs = require('node:fs');
const path = require('node:path');
const log = require('./logger');

const CONFIG_PATH = path.join(
  process.env.HOME || '/tmp',
  '.config',
  'axinova',
  'local-console-routing.json'
);

// Built-in defaults — aliasMap in the JSON file is additive
const BUILTIN_ALIASES = {
  'local-general': 'qwen2.5:7b',
  'local-code': 'qwen2.5-coder:7b',
  'local-code-large': 'qwen2.5-coder:14b',
  'local-gemma': 'gemma3:4b',
};

let state = null;

function defaultState() {
  return {
    aliasMap: {},
    channelDefaults: {},
    userOverrides: {},
  };
}

function load() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    state = JSON.parse(raw);
    log.info('Loaded routing config', { path: CONFIG_PATH });
  } catch {
    state = defaultState();
    log.info('Using default routing config (no file found)');
  }
}

function save() {
  const dir = path.dirname(CONFIG_PATH);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = CONFIG_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + '\n');
  fs.renameSync(tmp, CONFIG_PATH); // atomic on same FS
  log.info('Saved routing config', { path: CONFIG_PATH });
}

/** Merged alias map: built-in + user-defined from JSON */
function getAliasMap() {
  if (!state) load();
  return { ...BUILTIN_ALIASES, ...(state.aliasMap || {}) };
}

/** Resolve an alias name to an Ollama model tag */
function resolveAlias(alias) {
  const map = getAliasMap();
  return map[alias] || null;
}

/**
 * Resolve the model for a given channel + user.
 * Priority: user override > channel default > 'local-general'
 */
function resolveModel(channelId, userId) {
  if (!state) load();
  const alias =
    state.userOverrides?.[userId] ||
    state.channelDefaults?.[channelId] ||
    'local-general';
  const model = resolveAlias(alias);
  return { alias, model: model || BUILTIN_ALIASES['local-general'] };
}

function setChannelDefault(channelId, alias) {
  if (!state) load();
  state.channelDefaults[channelId] = alias;
  save();
}

function setUserOverride(userId, alias) {
  if (!state) load();
  if (alias === null) {
    delete state.userOverrides[userId];
  } else {
    state.userOverrides[userId] = alias;
  }
  save();
}

module.exports = {
  getAliasMap,
  resolveAlias,
  resolveModel,
  setChannelDefault,
  setUserOverride,
  load,
  BUILTIN_ALIASES,
};
