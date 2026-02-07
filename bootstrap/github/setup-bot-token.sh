#!/usr/bin/env bash
set -euo pipefail

# Configure GitHub bot token for agent

AGENT_NUM="${1:-1}"
AGENT_NAME="axinova-agent${AGENT_NUM}-bot"

echo "==> Setting up GitHub authentication for $AGENT_NAME"

# Check if 1Password CLI is available
if ! command -v op &>/dev/null; then
  echo "Error: 1Password CLI not installed. Run: brew install --cask 1password-cli"
  exit 1
fi

# Retrieve token from 1Password
TOKEN_ITEM="GitHub Bot Token - Agent${AGENT_NUM}"
echo "→ Retrieving token from 1Password vault..."

if ! GITHUB_TOKEN=$(op item get "$TOKEN_ITEM" --fields password 2>/dev/null); then
  echo "Error: Token not found in 1Password"
  echo "Create it first with:"
  echo "  op item create --category=password --title='$TOKEN_ITEM' --vault='Axinova' password='<token>'"
  exit 1
fi

# Configure git
echo "→ Configuring git identity..."
git config --global user.name "Axinova Agent ${AGENT_NUM} Bot"
git config --global user.email "agent${AGENT_NUM}@axinova-ai.com"

# Authenticate with GitHub CLI
echo "→ Authenticating with GitHub CLI..."
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Verify authentication
echo ""
echo "→ Verifying authentication..."
if gh auth status; then
  echo "✅ GitHub authentication successful"
else
  echo "❌ Authentication failed"
  exit 1
fi

# Test repo access
echo ""
echo "→ Testing repository access..."
if gh repo list axinova-ai --limit 5; then
  echo "✅ Can access axinova-ai repositories"
else
  echo "⚠️  Limited repository access (check token scopes)"
fi

echo ""
echo "✅ GitHub bot setup complete for $AGENT_NAME"
echo ""
echo "Environment variables to set in agent runtime:"
echo "  export GITHUB_TOKEN=\$(op item get '$TOKEN_ITEM' --fields password)"
echo "  export GITHUB_USER=$AGENT_NAME"
