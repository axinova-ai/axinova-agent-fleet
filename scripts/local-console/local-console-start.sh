#!/usr/bin/env bash
set -euo pipefail

# Local Console Bot Starter — Sources env file and starts the bot
# Used by com.axinova.local-console-bot.plist since launchd can't source .env files

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Source secrets
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/discord-local-console.env" ]] && set -a && eval "$(cat "$HOME/.config/axinova/discord-local-console.env")" && set +a

if [[ -z "${DISCORD_TOKEN:-}" ]]; then
  echo "FATAL: DISCORD_TOKEN not set. Check ~/.config/axinova/discord-local-console.env"
  exit 1
fi

BOT_DIR="$(cd "$(dirname "$0")/../../integrations/discord-local-console" && pwd)"
cd "$BOT_DIR"

exec node index.js
