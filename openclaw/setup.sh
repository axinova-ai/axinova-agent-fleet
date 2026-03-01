#!/usr/bin/env bash
set -euo pipefail

# Idempotent OpenClaw + Discord Setup for Axinova Agent Fleet
# Re-runnable: skips already-completed steps
#
# Prerequisites:
#   - npm installed
#   - Discord bot created (see Step 1 in plan)
#   - DISCORD_BOT_TOKEN, DISCORD_SERVER_ID, DISCORD_USER_ID set (or prompted)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$HOME/.config/axinova"
OPENCLAW_DIR="$HOME/.openclaw"

echo "==> OpenClaw + Discord Setup for Axinova Agent Fleet"
echo ""

# --- Step 1: Install OpenClaw ---

echo "→ [1/8] Checking OpenClaw installation..."
if ! command -v openclaw &>/dev/null; then
  echo "  Installing OpenClaw..."
  npm install -g openclaw@latest
  echo "  Installed: $(openclaw --version 2>/dev/null || echo 'done')"
else
  echo "  Already installed: $(openclaw --version 2>/dev/null || echo 'unknown')"
fi

# --- Step 2: Collect Discord credentials ---

echo ""
echo "→ [2/8] Collecting Discord credentials..."

if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
  echo "  DISCORD_BOT_TOKEN not set in environment."
  echo -n "  Enter Discord bot token: "
  read -rs DISCORD_BOT_TOKEN
  echo ""
fi

if [[ -z "${DISCORD_SERVER_ID:-}" ]]; then
  echo -n "  Enter Discord server (guild) ID: "
  read -r DISCORD_SERVER_ID
fi

if [[ -z "${DISCORD_USER_ID:-}" ]]; then
  echo -n "  Enter your Discord user ID: "
  read -r DISCORD_USER_ID
fi

export DISCORD_BOT_TOKEN DISCORD_SERVER_ID DISCORD_USER_ID

echo "  Server ID: $DISCORD_SERVER_ID"
echo "  User ID: $DISCORD_USER_ID"
echo "  Bot token: ${DISCORD_BOT_TOKEN:0:10}..."

# --- Step 3: Run Discord channel + webhook setup ---

echo ""
echo "→ [3/8] Setting up Discord channels and webhooks..."
bash "$SCRIPT_DIR/discord-setup.sh"

# Source the generated webhook env
if [[ -f "$CONFIG_DIR/discord-webhooks.env" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/discord-webhooks.env"
  echo "  Loaded webhook config from $CONFIG_DIR/discord-webhooks.env"
else
  echo "  WARNING: discord-webhooks.env not generated"
fi

# --- Step 4: Create OpenClaw workspace ---

echo ""
echo "→ [4/8] Creating OpenClaw workspace..."
mkdir -p "$OPENCLAW_DIR"

# --- Step 5: Write OpenClaw config ---

echo ""
echo "→ [5/8] Writing OpenClaw config..."

# Read template and substitute env vars
OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"

# Use envsubst for variable substitution
if command -v envsubst &>/dev/null; then
  export DISCORD_CHANNEL_TASKS="${DISCORD_CHANNEL_TASKS:-}"
  envsubst < "$SCRIPT_DIR/openclaw.json" > "$OPENCLAW_CONFIG"
else
  # Fallback: sed-based substitution
  sed \
    -e "s|\${DISCORD_BOT_TOKEN}|${DISCORD_BOT_TOKEN}|g" \
    -e "s|\${DISCORD_SERVER_ID}|${DISCORD_SERVER_ID}|g" \
    -e "s|\${DISCORD_USER_ID}|${DISCORD_USER_ID}|g" \
    -e "s|\${DISCORD_CHANNEL_TASKS}|${DISCORD_CHANNEL_TASKS:-}|g" \
    "$SCRIPT_DIR/openclaw.json" > "$OPENCLAW_CONFIG"
fi

chmod 600 "$OPENCLAW_CONFIG"
echo "  Config written to $OPENCLAW_CONFIG"

# --- Step 6: Copy task-router prompt ---

echo ""
echo "→ [6/8] Copying agent prompts..."
AGENT_DIR="$OPENCLAW_DIR/agents/task-router"
mkdir -p "$AGENT_DIR"
cp "$SCRIPT_DIR/task-router-prompt.md" "$AGENT_DIR/system-prompt.md"
echo "  Copied task-router-prompt.md → $AGENT_DIR/system-prompt.md"

# --- Step 7: Pairing ---

echo ""
echo "→ [7/8] Checking pairing status..."

# Check if gateway can start (pairing status)
if openclaw pairing status &>/dev/null 2>&1; then
  echo "  Already paired."
else
  echo "  Starting pairing process..."
  echo "  Send a DM to the bot in Discord, then run:"
  echo "    openclaw pairing approve"
  echo ""
  echo "  Press Enter after you've sent a DM and approved pairing..."
  read -r
  openclaw pairing approve 2>/dev/null || {
    echo "  Pairing may need manual completion. Continue anyway."
  }
fi

# --- Step 8: Install launchd daemon ---

echo ""
echo "→ [8/8] Installing launchd daemon..."
PLIST_SRC="$FLEET_DIR/launchd/com.axinova.openclaw.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.axinova.openclaw.plist"

if [[ ! -f "$PLIST_SRC" ]]; then
  echo "  WARNING: launchd plist not found at $PLIST_SRC"
else
  mkdir -p "$HOME/Library/LaunchAgents"

  # Unload if already loaded (to pick up config changes)
  if launchctl list com.axinova.openclaw &>/dev/null 2>&1; then
    echo "  Unloading existing daemon..."
    launchctl unload "$PLIST_DST" 2>/dev/null || true
  fi

  cp "$PLIST_SRC" "$PLIST_DST"
  launchctl load "$PLIST_DST"
  echo "  Daemon loaded: $PLIST_DST"
fi

# --- Step 9: Verify ---

echo ""
echo "→ Verifying setup..."

# Test webhook
if [[ -n "${DISCORD_WEBHOOK_LOGS:-}" ]]; then
  echo "  Sending test message to #agent-logs..."
  curl -sf -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"Agent Fleet Online\",\"description\":\"OpenClaw setup completed on $(hostname -s) at $(date '+%Y-%m-%d %H:%M:%S')\",\"color\":5814783}]}" \
    "$DISCORD_WEBHOOK_LOGS" >/dev/null && echo "  Test message sent!" || echo "  WARNING: Test message failed"
else
  echo "  Skipping webhook test (no DISCORD_WEBHOOK_LOGS)"
fi

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Send a DM to the bot if pairing isn't done"
echo "  2. Post in #agent-tasks: 'Add health check to miniapp-builder-go'"
echo "  3. Check logs: tail -f ~/logs/openclaw-stdout.log"
echo ""
echo "Config files:"
echo "  $OPENCLAW_CONFIG"
echo "  $CONFIG_DIR/discord-webhooks.env"
