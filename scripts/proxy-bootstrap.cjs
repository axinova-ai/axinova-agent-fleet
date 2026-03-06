/**
 * proxy-bootstrap.cjs
 *
 * Minimal Node.js proxy interceptor for OpenClaw running behind China's GFW.
 * Patches http.globalAgent and https.globalAgent to route through a SOCKS5 proxy.
 * Loaded via NODE_OPTIONS="-r /path/to/proxy-bootstrap.cjs"
 *
 * Requires: socks-proxy-agent (dependency of many npm packages, likely already present)
 * Falls back gracefully if socks-proxy-agent is not available.
 */
'use strict';

const http = require('http');
const https = require('https');
const net = require('net');

const PROXY = process.env.SOCKS5_PROXY || 'socks5://127.0.0.1:1080';
const NO_PROXY = (process.env.NO_PROXY || 'localhost,127.0.0.1').split(',').map(s => s.trim());

function isNoProxy(host) {
  if (!host) return false;
  return NO_PROXY.some(pattern => {
    if (pattern.startsWith('*')) return host.endsWith(pattern.slice(1));
    return host === pattern || host.endsWith('.' + pattern);
  });
}

// Try to load socks-proxy-agent from openclaw's own node_modules first
function findSocksAgent() {
  const searchPaths = [
    // openclaw global install
    '/opt/homebrew/lib/node_modules/openclaw/node_modules/socks-proxy-agent',
    '/usr/local/lib/node_modules/openclaw/node_modules/socks-proxy-agent',
    // global node_modules
    '/opt/homebrew/lib/node_modules/socks-proxy-agent',
    '/usr/local/lib/node_modules/socks-proxy-agent',
  ];

  for (const p of searchPaths) {
    try {
      const mod = require(p);
      return mod.SocksProxyAgent || mod.default || mod;
    } catch (_) {}
  }

  // Last resort: bare require (works if installed globally)
  try {
    const mod = require('socks-proxy-agent');
    return mod.SocksProxyAgent || mod.default || mod;
  } catch (_) {}

  return null;
}

const SocksProxyAgent = findSocksAgent();

if (!SocksProxyAgent) {
  // Fallback: patch net.Socket.connect to intercept raw TCP connections
  // This works for WebSocket connections which bypass http.globalAgent
  const originalConnect = net.Socket.prototype.connect;
  net.Socket.prototype.connect = function(options, ...args) {
    const host = (typeof options === 'object' ? options.host : null) || '';
    if (!isNoProxy(host) && host && !net.isIP(host)) {
      // Can't proxy without socks-proxy-agent — log warning only once
      if (!process.env._PROXY_WARN_SHOWN) {
        process.env._PROXY_WARN_SHOWN = '1';
        process.stderr.write(
          '[proxy-bootstrap] WARNING: socks-proxy-agent not found. ' +
          'Install with: npm install -g socks-proxy-agent\n'
        );
      }
    }
    return originalConnect.call(this, options, ...args);
  };
  return;
}

const agent = new SocksProxyAgent(PROXY);

// Patch http.globalAgent and https.globalAgent
const origHttpRequest = http.request.bind(http);
const origHttpsRequest = https.request.bind(https);

function patchOptions(options) {
  if (typeof options === 'string') {
    try { options = new URL(options); } catch (_) { return options; }
  }
  const host = options.hostname || options.host || '';
  if (isNoProxy(host)) return options;
  return Object.assign({}, options, { agent });
}

http.request = function(options, callback) {
  return origHttpRequest(patchOptions(options), callback);
};
https.request = function(options, callback) {
  return origHttpsRequest(patchOptions(options), callback);
};

// Also patch the default global agents
http.globalAgent = agent;
https.globalAgent = agent;

process.stderr.write(`[proxy-bootstrap] SOCKS5 proxy active: ${PROXY}\n`);
