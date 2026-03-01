#!/usr/bin/env bash
set -euo pipefail

# Axinova Agent Fleet - Tailscale + Remote Access Hardening
# Installs Tailscale, hardens SSH, enables Screen Sharing, configures headless power.
# Run on each Mac mini as your admin user (not root).
# Usage: ./setup-tailscale.sh [hostname]
#   hostname: optional MagicDNS hostname (e.g. agent01, focusagent02)
#             auto-detected from machine hostname if omitted

echo "==> Tailscale + Remote Access Setup"

# Refuse root
if [[ $EUID -eq 0 ]]; then
  echo "Error: Do not run this script as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Determine hostname ---
if [[ -n "${1:-}" ]]; then
  TS_HOSTNAME="$1"
else
  HOSTNAME_SHORT=$(hostname -s | tr '[:upper:]' '[:lower:]')
  if [[ "$HOSTNAME_SHORT" == *"m4"* ]]; then
    TS_HOSTNAME="agent01"
  elif [[ "$HOSTNAME_SHORT" == *"m2"* ]]; then
    TS_HOSTNAME="focusagent02"
  else
    TS_HOSTNAME="$HOSTNAME_SHORT"
  fi
fi
echo "→ Tailscale hostname will be: $TS_HOSTNAME"

# ============================================================
# 1. Install Tailscale
# ============================================================
echo ""
echo "==> Step 1: Install Tailscale"

if [[ -d "/Applications/Tailscale.app" ]]; then
  echo "→ Tailscale.app already installed"
else
  echo "→ Installing Tailscale via Homebrew..."
  brew install --cask tailscale
fi

# ============================================================
# 2. Launch Tailscale and login
# ============================================================
echo ""
echo "==> Step 2: Launch Tailscale and login"

# Determine CLI path
if command -v tailscale &>/dev/null; then
  TAILSCALE_CLI="tailscale"
elif [[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
  TAILSCALE_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
else
  echo "Error: Tailscale CLI not found. Ensure Tailscale.app is installed."
  exit 1
fi

# Launch the app if not running
if ! pgrep -x "Tailscale" &>/dev/null; then
  echo "→ Starting Tailscale.app..."
  open -a Tailscale
  sleep 3
fi

# Check if already logged in
if $TAILSCALE_CLI status &>/dev/null; then
  echo "→ Already logged in to Tailscale"
else
  echo "→ Logging in to Tailscale..."
  echo "  A browser window will open for authentication."
  echo "  Complete the login, then return here."
  $TAILSCALE_CLI up --hostname="$TS_HOSTNAME"
  echo "→ Tailscale login complete"
fi

# Set hostname if not already set
CURRENT_HOSTNAME=$($TAILSCALE_CLI status --json 2>/dev/null | grep -o '"Self":{"[^}]*"HostName":"[^"]*"' | sed 's/.*"HostName":"\([^"]*\)"/\1/' || echo "")
if [[ "$CURRENT_HOSTNAME" != "$TS_HOSTNAME" ]]; then
  echo "→ Setting Tailscale hostname to $TS_HOSTNAME..."
  $TAILSCALE_CLI set --hostname="$TS_HOSTNAME"
fi

# ============================================================
# 3. Enable and harden SSH (Remote Login)
# ============================================================
echo ""
echo "==> Step 3: Enable and harden SSH"

# Enable Remote Login
REMOTE_LOGIN=$(sudo systemsetup -getremotelogin 2>/dev/null | awk '{print $NF}')
if [[ "$REMOTE_LOGIN" != "On" ]]; then
  echo "→ Enabling Remote Login (SSH)..."
  sudo systemsetup -setremotelogin on
else
  echo "→ Remote Login already enabled"
fi

# Harden sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"
if grep -q "^PasswordAuthentication no" "$SSHD_CONFIG" 2>/dev/null; then
  echo "→ SSH already hardened (password auth disabled)"
else
  echo "→ Hardening SSH config (disabling password auth)..."
  # Backup original
  if [[ ! -f "${SSHD_CONFIG}.bak.pre-tailscale" ]]; then
    sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.pre-tailscale"
    echo "  Backup saved to ${SSHD_CONFIG}.bak.pre-tailscale"
  fi

  # Disable password authentication
  if grep -q "^#*PasswordAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i '' 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
  else
    echo "PasswordAuthentication no" | sudo tee -a "$SSHD_CONFIG" >/dev/null
  fi

  # Disable keyboard-interactive authentication
  if grep -q "^#*KbdInteractiveAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i '' 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG"
  else
    echo "KbdInteractiveAuthentication no" | sudo tee -a "$SSHD_CONFIG" >/dev/null
  fi

  # Also handle legacy ChallengeResponseAuthentication
  if grep -q "^#*ChallengeResponseAuthentication" "$SSHD_CONFIG"; then
    sudo sed -i '' 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
  fi

  echo "→ SSH config hardened. Restarting SSH..."
  # macOS uses launchctl for sshd
  sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
fi

# ============================================================
# 4. Enable Screen Sharing
# ============================================================
echo ""
echo "==> Step 4: Enable Screen Sharing"

# Check if Screen Sharing is loaded
if sudo launchctl list | grep -q "com.apple.screensharing"; then
  echo "→ Screen Sharing already enabled"
else
  echo "→ Enabling Screen Sharing..."
  sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
fi

# Restrict Screen Sharing to specific users via dseditgroup
# Add axinova-agent and current admin user to com.apple.access_screensharing
echo "→ Configuring Screen Sharing access..."
for USER in "axinova-agent" "$(whoami)"; do
  if dseditgroup -o checkmember -m "$USER" com.apple.access_screensharing &>/dev/null; then
    echo "  $USER already in Screen Sharing group"
  else
    echo "  Adding $USER to Screen Sharing access..."
    sudo dseditgroup -o edit -a "$USER" -t user com.apple.access_screensharing
  fi
done

# ============================================================
# 5. Configure headless power settings
# ============================================================
echo ""
echo "==> Step 5: Configure headless power settings"

echo "→ Setting power management for headless operation..."
# Never sleep
sudo pmset -a sleep 0
sudo pmset -a disablesleep 1
# Wake on network access (Wake-on-LAN)
sudo pmset -a womp 1
# Auto restart after power failure
sudo pmset -a autorestart 1
# Display sleep after 10 minutes (saves energy, doesn't affect VNC)
sudo pmset -a displaysleep 10

echo "→ Power settings configured"

# ============================================================
# 6. Verification
# ============================================================
echo ""
echo "==> Verification"

# Tailscale IP
TS_IP=$($TAILSCALE_CLI ip -4 2>/dev/null || echo "unknown")
TS_STATUS=$($TAILSCALE_CLI status --self --json 2>/dev/null | grep -o '"Online":true' &>/dev/null && echo "online" || echo "check status")

echo "  Tailscale IP:        $TS_IP"
echo "  Tailscale hostname:  $TS_HOSTNAME"
echo "  MagicDNS name:       $TS_HOSTNAME (use: ssh user@$TS_HOSTNAME)"
echo "  Tailscale status:    $TS_STATUS"
echo "  SSH:                 enabled (key-only, password auth disabled)"
echo "  Screen Sharing:      enabled (restricted to axinova-agent + $(whoami))"
echo "  Power:               sleep disabled, wake-on-LAN on, auto-restart on"

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "  1. On your MacBook, install Tailscale and login to the same tailnet"
echo "  2. Deploy SSH keys: ssh-copy-id axinova-agent@$TS_HOSTNAME"
echo "  3. Test SSH:        ssh axinova-agent@$TS_HOSTNAME"
echo "  4. Test VNC:        open vnc://$TS_HOSTNAME"
echo "  5. Verify mesh:     tailscale ping $TS_HOSTNAME"
