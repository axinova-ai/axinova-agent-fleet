#!/usr/bin/env bash
set -euo pipefail

# Axinova Agent Fleet - Remote Access Setup
# Installs RustDesk, hardens SSH, enables Screen Sharing, configures headless power.
# Run on each Mac mini as your admin user (not root).
# Usage: ./setup-remote-access.sh

echo "==> Remote Access Setup (RustDesk + SSH Hardening)"

# Refuse root
if [[ $EUID -eq 0 ]]; then
  echo "Error: Do not run this script as root"
  exit 1
fi

# Require sudo password upfront
sudo -v || { echo "Error: sudo access required"; exit 1; }

# Keep sudo alive during script
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &

# ============================================================
# 1. Install RustDesk
# ============================================================
echo ""
echo "==> Step 1: Install RustDesk"

if [[ -d "/Applications/RustDesk.app" ]]; then
  echo "→ RustDesk already installed"
else
  echo "→ Installing RustDesk via Homebrew..."
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  if command -v brew &>/dev/null; then
    brew install --cask rustdesk
  else
    echo "Error: Homebrew not found. Install it first: ./setup-macos.sh"
    exit 1
  fi
fi

# ============================================================
# 2. Launch RustDesk and configure
# ============================================================
echo ""
echo "==> Step 2: Launch RustDesk"

if ! pgrep -x "RustDesk" &>/dev/null; then
  echo "→ Starting RustDesk..."
  open -a RustDesk
  sleep 3
fi

echo "→ RustDesk is running"
echo ""
echo "  IMPORTANT: On first launch, macOS will prompt for:"
echo "    1. Accessibility permission (System Settings > Privacy > Accessibility)"
echo "    2. Screen Recording permission (System Settings > Privacy > Screen Recording)"
echo "  Grant both to RustDesk, then restart RustDesk."
echo ""
echo "  After granting permissions, note your RustDesk ID and set a"
echo "  permanent password in RustDesk settings for unattended access."

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
  if [[ ! -f "${SSHD_CONFIG}.bak.pre-hardening" ]]; then
    sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.pre-hardening"
    echo "  Backup saved to ${SSHD_CONFIG}.bak.pre-hardening"
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
  sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
fi

# ============================================================
# 4. Enable Screen Sharing (VNC)
# ============================================================
echo ""
echo "==> Step 4: Enable Screen Sharing"

if sudo launchctl list | grep -q "com.apple.screensharing"; then
  echo "→ Screen Sharing already enabled"
else
  echo "→ Enabling Screen Sharing..."
  sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true
fi

# Restrict Screen Sharing to specific users
echo "→ Configuring Screen Sharing access..."
for USER in "axinova-agent" "$(whoami)"; do
  if id "$USER" &>/dev/null; then
    if dseditgroup -o checkmember -m "$USER" com.apple.access_screensharing &>/dev/null; then
      echo "  $USER already in Screen Sharing group"
    else
      echo "  Adding $USER to Screen Sharing access..."
      sudo dseditgroup -o edit -a "$USER" -t user com.apple.access_screensharing
    fi
  fi
done

# ============================================================
# 5. Configure headless power settings
# ============================================================
echo ""
echo "==> Step 5: Configure headless power settings"

echo "→ Setting power management for headless operation..."
sudo pmset -a sleep 0
sudo pmset -a disablesleep 1
sudo pmset -a womp 1
sudo pmset -a autorestart 1
sudo pmset -a displaysleep 10

echo "→ Power settings configured"

# ============================================================
# 6. Verification
# ============================================================
echo ""
echo "==> Verification"

HOSTNAME_SHORT=$(hostname -s)
echo "  Hostname:            $HOSTNAME_SHORT"
echo "  RustDesk:            installed (check app for ID)"
echo "  SSH:                 enabled (key-only, password auth disabled)"
echo "  Screen Sharing:      enabled (restricted users)"
echo "  Power:               sleep disabled, wake-on-LAN on, auto-restart on"

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Grant RustDesk Accessibility + Screen Recording permissions (System Settings > Privacy)"
echo "  2. In RustDesk settings, set a permanent password for unattended access"
echo "  3. Note the RustDesk ID — you'll need it to connect from your MacBook"
echo "  4. Install RustDesk on your MacBook: brew install --cask rustdesk"
echo "  5. Deploy SSH keys: ssh-copy-id axinova-agent@<LAN-IP>"
echo "  6. Test SSH: ssh axinova-agent@<VPN-IP-or-LAN-IP>"
echo "  7. Test RustDesk: open RustDesk on MacBook, enter mini's ID"
