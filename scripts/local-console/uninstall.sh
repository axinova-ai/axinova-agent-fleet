#!/usr/bin/env bash
set -euo pipefail

# Uninstall Local Console Bot — stop service and remove plist

PLIST_DST="$HOME/Library/LaunchAgents/com.axinova.local-console-bot.plist"

echo "=== Local Console Bot Uninstall ==="

if [[ -f "$PLIST_DST" ]]; then
  echo "Unloading launchd plist..."
  launchctl unload "$PLIST_DST" 2>/dev/null || true
  rm -f "$PLIST_DST"
  echo "Removed $PLIST_DST"
else
  echo "Plist not found at $PLIST_DST (already uninstalled?)"
fi

echo ""
echo "Note: Env file and logs are preserved."
echo "  Env:  ~/.config/axinova/discord-local-console.env"
echo "  Logs: ~/logs/local-console-bot-*.log"
echo "  App:  ~/.config/axinova/logs/local-console.log"
