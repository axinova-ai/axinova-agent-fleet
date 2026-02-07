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

# Step 4: Create axinova-agent user (if not exists)
echo "→ Creating axinova-agent user..."
if ! dscl . -read /Users/axinova-agent &>/dev/null; then
  "$SCRIPT_DIR/create-agent-user.sh"
else
  echo "  User axinova-agent already exists"
fi

# Step 5: Set up SSH for axinova-agent
echo "→ Setting up SSH keys for axinova-agent..."
sudo -u axinova-agent bash <<'EOF'
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -C "axinova-agent@mac-mini" -f ~/.ssh/id_ed25519 -N ""
  echo "  SSH public key:"
  cat ~/.ssh/id_ed25519.pub
else
  echo "  SSH key already exists"
fi
EOF

# Step 6: Configure sudoers for specific commands
echo "→ Configuring sudoers for axinova-agent..."
SUDOERS_FILE="/etc/sudoers.d/axinova-agent"
if [[ ! -f "$SUDOERS_FILE" ]]; then
  sudo tee "$SUDOERS_FILE" > /dev/null <<EOF
# Axinova agent user - limited sudo permissions
axinova-agent ALL=(ALL) NOPASSWD: /usr/bin/systemctl
axinova-agent ALL=(ALL) NOPASSWD: /usr/sbin/wg-quick
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

echo ""
echo "✅ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Switch to axinova-agent user: sudo -i -u axinova-agent"
echo "2. Configure GitHub bot token: export GITHUB_TOKEN=<token>"
echo "3. Set up WireGuard VPN: cd ~/workspace/axinova-agent-fleet/bootstrap/vpn && ./wireguard-install.sh"
echo "4. Configure MCP server: cp config-example.json ~/.config/claude/config.json"
