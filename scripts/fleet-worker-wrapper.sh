#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Source secrets (same pattern as agent-launcher.sh)
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/vikunja.env" ]] && source "$HOME/.config/axinova/vikunja.env"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/secrets.env" ]] && source "$HOME/.config/axinova/secrets.env"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/discord-webhooks.env" ]] && source "$HOME/.config/axinova/discord-webhooks.env"

AGENT_ID="${1:?Usage: fleet-worker-wrapper.sh <agent-id>}"
WORKSPACE="${2:-$HOME/workspace}"

exec "$HOME/workspace/axinova-fleet-go/bin/fleet-worker" \
  --agent-id="$AGENT_ID" \
  --workspace="$WORKSPACE"
