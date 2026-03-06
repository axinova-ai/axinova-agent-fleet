#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Gateway Starter — Sources env files and starts the gateway
# Used by com.axinova.openclaw.plist since launchd can't source .env files

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Source secrets
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/discord-bot.env" ]] && set -a && eval "$(cat "$HOME/.config/axinova/discord-bot.env")" && set +a
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/discord-webhooks.env" ]] && set -a && eval "$(grep -v '^#' "$HOME/.config/axinova/discord-webhooks.env" | grep -v '^$' | grep '=')" && set +a
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/moonshot.env" ]] && set -a && eval "$(cat "$HOME/.config/axinova/moonshot.env")" && set +a

# Note: OpenClaw model auth is configured via `openclaw models auth paste-token`
# and stored in ~/.openclaw/agents/main/agent/auth-profiles.json
# Discord bot token is configured via `openclaw channels add --channel discord --token ...`
# and stored in ~/.openclaw/openclaw.json (not from env vars)

# --- GFW bypass: SOCKS5 tunnel via Singapore VPN for Discord WebSocket ---
# Discord is blocked in China. Route all OpenClaw traffic through the VPN server.
# Uses global-agent to intercept Node.js HTTP/HTTPS/WebSocket at the global level.
VPN_SERVER="8.222.187.10"
SOCKS_PORT="1080"

# Start SSH SOCKS5 tunnel if not already running
if ! nc -z 127.0.0.1 "$SOCKS_PORT" 2>/dev/null; then
  ssh -N -f \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -i "$HOME/.ssh/id_ed25519" \
    -D "127.0.0.1:${SOCKS_PORT}" \
    "root@${VPN_SERVER}" 2>/dev/null &
  sleep 2
fi

# Route all Node.js connections through SOCKS5 proxy (bypass GFW for Discord)
export GLOBAL_AGENT_HTTP_PROXY="socks5://127.0.0.1:${SOCKS_PORT}"
# Don't proxy local/VPN traffic
export GLOBAL_AGENT_NO_PROXY="localhost,127.0.0.1,10.66.66.*,192.168.3.*,api.moonshot.cn"
# Load global-agent to intercept all Node.js HTTP/WebSocket connections
export NODE_OPTIONS="-r global-agent/bootstrap"

# Start the OpenClaw gateway
exec openclaw gateway
