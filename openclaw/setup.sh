#!/usr/bin/env bash
set -euo pipefail

# OpenClaw + Discord Setup for Axinova Agent Fleet
# Run on M4 Mac Mini as axinova-agent user

echo "==> OpenClaw + Discord Setup"

# Check prerequisites
if ! command -v npm &>/dev/null; then
  echo "Error: npm not installed"
  exit 1
fi

# Step 1: Install OpenClaw
echo "→ Installing OpenClaw..."
if ! command -v openclaw &>/dev/null; then
  npm install -g openclaw@latest
else
  echo "  OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'unknown')"
fi

# Step 2: Run onboarding
echo "→ Running OpenClaw onboarding..."
echo ""
echo "You'll need:"
echo "  1. Discord bot token (from Discord Developer Portal)"
echo "  2. Anthropic API key (from console.anthropic.com)"
echo ""

openclaw onboard --install-daemon

# Step 3: Configure Vikunja integration
echo ""
echo "→ Setting up Vikunja task routing..."
echo ""
echo "Configure these command handlers in OpenClaw config:"
echo ""
echo "  /task <description>  → Create Vikunja task"
echo "    Auto-label rules:"
echo "    - Keywords: api, backend, go, endpoint → backend-sde"
echo "    - Keywords: ui, vue, component, frontend → frontend-sde"
echo "    - Keywords: deploy, docker, infra → devops"
echo "    - Keywords: test, qa, coverage → qa"
echo "    - Keywords: docs, wiki, runbook → docs"
echo ""
echo "  /status → Query Vikunja for in-progress tasks"
echo "  /deploy <service> <env> → Trigger deployment"
echo ""

# Step 4: Install launchd daemon
FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_SRC="$FLEET_DIR/launchd/com.axinova.openclaw.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.axinova.openclaw.plist"

if [[ -f "$PLIST_SRC" ]]; then
  echo "→ Installing launchd daemon..."
  mkdir -p "$HOME/Library/LaunchAgents"
  cp "$PLIST_SRC" "$PLIST_DST"
  launchctl load "$PLIST_DST" 2>/dev/null || true
  echo "  Daemon installed at: $PLIST_DST"
else
  echo "  Warning: launchd plist not found at $PLIST_SRC"
fi

echo ""
echo "✅ OpenClaw setup complete!"
echo ""
echo "Test: Send a message in your Discord #agent-tasks channel"
echo "Logs: tail -f ~/logs/openclaw-stdout.log"
