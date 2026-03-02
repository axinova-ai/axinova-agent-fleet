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

# Start the OpenClaw gateway
exec openclaw gateway
