#!/usr/bin/env bash
set -euo pipefail

# Install Local Console Bot — npm ci, env stub, launchd plist

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BOT_DIR="$FLEET_DIR/integrations/discord-local-console"
PLIST_SRC="$FLEET_DIR/launchd/com.axinova.local-console-bot.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.axinova.local-console-bot.plist"
ENV_FILE="$HOME/.config/axinova/discord-local-console.env"

echo "=== Local Console Bot Install ==="

# 1. npm ci
echo "[1/4] Installing dependencies..."
cd "$BOT_DIR"
npm ci --production

# 2. Create env file stub if missing
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[2/4] Creating env file stub..."
  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<'EOF'
# Local Console Bot — Discord token
# Get from https://discord.com/developers/applications
DISCORD_TOKEN=

# Ollama URL (default: localhost tunnel from M2 Pro)
OLLAMA_BASE_URL=http://localhost:11434
EOF
  chmod 600 "$ENV_FILE"
  echo "  Created $ENV_FILE — edit it to add your DISCORD_TOKEN"
else
  echo "[2/4] Env file exists: $ENV_FILE"
fi

# 3. Create logs directory
echo "[3/4] Ensuring log directories..."
mkdir -p "$HOME/logs"
mkdir -p "$HOME/.config/axinova/logs"

# 4. Install + load plist
echo "[4/4] Installing launchd plist..."
if [[ ! -f "$PLIST_SRC" ]]; then
  echo "  ERROR: Plist not found at $PLIST_SRC"
  exit 1
fi

# Unload existing if present
launchctl unload "$PLIST_DST" 2>/dev/null || true

cp "$PLIST_SRC" "$PLIST_DST"

# Substitute HOME path in plist for current user
sed -i '' "s|/Users/agent01|$HOME|g" "$PLIST_DST"

launchctl load "$PLIST_DST"

echo ""
echo "=== Done ==="
echo "Check status:  launchctl list | grep local-console"
echo "View logs:     tail -f ~/logs/local-console-bot-stdout.log"
echo ""
echo "IMPORTANT: Edit $ENV_FILE and set DISCORD_TOKEN before the bot can connect."
