#!/usr/bin/env bash
set -euo pipefail

# Configure GitHub authentication for agent machine
# Uses your existing GitHub account with per-machine identity

echo "==> Setting up GitHub authentication"

HOSTNAME_SHORT=$(hostname -s | tr '[:upper:]' '[:lower:]')

# Determine machine label
if [[ "$HOSTNAME_SHORT" == *"m4"* ]]; then
  MACHINE_LABEL="M4"
elif [[ "$HOSTNAME_SHORT" == *"m2"* ]]; then
  MACHINE_LABEL="M2Pro"
else
  MACHINE_LABEL="$HOSTNAME_SHORT"
fi

# Step 1: Ensure SSH key exists
echo "→ Checking SSH key..."
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  echo "  Generating SSH key..."
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -C "axinova-${MACHINE_LABEL,,}-agent" -f ~/.ssh/id_ed25519 -N ""
fi

echo "  SSH public key (add to https://github.com/settings/keys):"
echo ""
cat ~/.ssh/id_ed25519.pub
echo ""

# Step 2: Authenticate GitHub CLI
echo "→ Authenticating GitHub CLI..."
echo "  Paste your fine-grained PAT (from https://github.com/settings/personal-access-tokens/new):"
gh auth login --with-token

# Step 3: Verify
echo ""
echo "→ Verifying authentication..."
if gh auth status; then
  echo "✅ GitHub authentication successful"
else
  echo "❌ Authentication failed"
  exit 1
fi

# Step 4: Test SSH
echo ""
echo "→ Testing SSH access..."
ssh -T git@github.com 2>&1 || true

# Step 5: Test repo access
echo ""
echo "→ Testing repository access..."
if gh repo list axinova-ai --limit 5; then
  echo "✅ Can access axinova-ai repositories"
else
  echo "⚠️  Limited repository access (check token scopes)"
fi

echo ""
echo "✅ GitHub setup complete for $MACHINE_LABEL"
echo ""
echo "Git identity: $(git config user.name) <$(git config user.email)>"
echo "Commits will show as: Axinova $MACHINE_LABEL Agent <${MACHINE_LABEL,,}@axinova.local>"
