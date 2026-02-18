#!/usr/bin/env bash
set -euo pipefail

# Axinova Agent Fleet - Mac Mini Bootstrap Script
# Usage: curl -fsSL https://raw.githubusercontent.com/.../setup-macos.sh | bash

echo "==> Axinova Agent Fleet Bootstrap"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  echo "Error: Do not run this script as root"
  exit 1
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Install Homebrew if not present
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for Apple Silicon
  if [[ $(uname -m) == "arm64" ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "→ Homebrew already installed"
fi

# Step 2: Install dependencies from Brewfile
echo "→ Installing dependencies via Brewfile..."
if [[ -f "$SCRIPT_DIR/Brewfile" ]]; then
  brew bundle --file="$SCRIPT_DIR/Brewfile"
else
  echo "Warning: Brewfile not found, skipping bundle install"
fi

# Step 3: Install Go tooling
echo "→ Installing Go tools..."
go install golang.org/x/vuln/cmd/govulncheck@latest
go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
go install github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Step 3b: Install Claude Code CLI
echo "→ Installing Claude Code CLI..."
if ! command -v claude &>/dev/null; then
  npm install -g @anthropic-ai/claude-code
else
  echo "  Claude Code already installed: $(claude --version)"
fi

# Step 4: Create axinova-agent user (if not exists)
echo "→ Creating axinova-agent user..."
if ! dscl . -read /Users/axinova-agent &>/dev/null; then
  "$SCRIPT_DIR/create-agent-user.sh"
else
  echo "  User axinova-agent already exists"
fi

# Step 5: Set up SSH keys and git identity for axinova-agent
echo "→ Setting up SSH keys for axinova-agent..."
HOSTNAME_SHORT=$(hostname -s | tr '[:upper:]' '[:lower:]')

# Determine machine label from hostname
if [[ "$HOSTNAME_SHORT" == *"m4"* ]]; then
  MACHINE_LABEL="m4"
  GIT_NAME="Axinova M4 Agent"
  GIT_EMAIL="m4@axinova.local"
elif [[ "$HOSTNAME_SHORT" == *"m2"* ]]; then
  MACHINE_LABEL="m2pro"
  GIT_NAME="Axinova M2Pro Agent"
  GIT_EMAIL="m2pro@axinova.local"
else
  MACHINE_LABEL="$HOSTNAME_SHORT"
  GIT_NAME="Axinova $HOSTNAME_SHORT Agent"
  GIT_EMAIL="${HOSTNAME_SHORT}@axinova.local"
fi

sudo -u axinova-agent bash <<EOF
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -C "axinova-${MACHINE_LABEL}-agent" -f ~/.ssh/id_ed25519 -N ""
  echo "  SSH public key (add to github.com/settings/keys):"
  cat ~/.ssh/id_ed25519.pub
else
  echo "  SSH key already exists"
fi

# Configure git identity for this machine
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
echo "  Git identity: $GIT_NAME <$GIT_EMAIL>"
EOF

# Step 6: Configure sudoers for specific commands
echo "→ Configuring sudoers for axinova-agent..."
SUDOERS_FILE="/etc/sudoers.d/axinova-agent"
if [[ ! -f "$SUDOERS_FILE" ]]; then
  sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Axinova agent user - limited sudo permissions
axinova-agent ALL=(ALL) NOPASSWD: /usr/bin/systemctl
axinova-agent ALL=(ALL) NOPASSWD: /usr/bin/docker
EOF
  sudo chmod 0440 "$SUDOERS_FILE"
else
  echo "  Sudoers file already exists"
fi

# Step 7: Clone axinova-agent-fleet repo
echo "→ Cloning axinova-agent-fleet repository..."
WORKSPACE_DIR="/Users/axinova-agent/workspace"
sudo -u axinova-agent mkdir -p "$WORKSPACE_DIR"
if [[ ! -d "$WORKSPACE_DIR/axinova-agent-fleet" ]]; then
  sudo -u axinova-agent git clone https://github.com/axinova-ai/axinova-agent-fleet.git "$WORKSPACE_DIR/axinova-agent-fleet"
else
  echo "  Repository already cloned"
fi

# Step 8: Verify installations
echo ""
echo "==> Verification"
echo "→ Go version: $(go version)"
echo "→ Node version: $(node --version)"
echo "→ Docker version: $(docker --version 2>/dev/null || echo 'Not running (start Docker Desktop)')"
echo "→ GitHub CLI: $(gh --version | head -n1)"
echo "→ Claude Code: $(claude --version 2>/dev/null || echo 'Not installed')"
echo "→ tmux: $(tmux -V 2>/dev/null || echo 'Not installed')"

echo ""
echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Add the SSH public key above to https://github.com/settings/keys"
echo "2. Switch to axinova-agent user: sudo -i -u axinova-agent"
echo "3. Auth GitHub CLI: gh auth login --with-token <<< '<your-PAT>'"
echo "4. Import AmneziaWG config: cd ~/workspace/axinova-agent-fleet/bootstrap/vpn && ./amneziawg-setup.sh"
echo "5. Configure Claude Code: export ANTHROPIC_API_KEY=<key> && claude auth login"
echo "6. Copy MCP config: cp integrations/mcp/agent-mcp-config.json ~/.claude/settings.json"
