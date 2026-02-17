#!/usr/bin/env bash
set -euo pipefail

# AmneziaWG VPN Setup for Mac Mini Agent Fleet
# Pre-requisite: brew install --cask amneziawg
# Pre-requisite: VPN configs already generated in vpn-distribution/configs/macos/

echo "==> AmneziaWG VPN Setup"

# Check AmneziaWG app is installed
if ! ls /Applications/AmneziaWG.app &>/dev/null; then
  echo "Error: AmneziaWG app not installed."
  echo "Install with: brew install --cask amneziawg"
  exit 1
fi

# Determine which config to use based on hostname
HOSTNAME=$(hostname -s)
FLEET_REPO="${FLEET_REPO:-$HOME/workspace/axinova-agent-fleet}"
CONFIG_DIR="$FLEET_REPO/vpn-distribution/configs/macos"

if [[ "$HOSTNAME" == *"m4"* ]]; then
  CONFIG_NAME="m4-agent-1"
  EXPECTED_IP="10.66.66.3"
elif [[ "$HOSTNAME" == *"m2"* ]]; then
  CONFIG_NAME="m2-pro-agent-2"
  EXPECTED_IP="10.66.66.2"
else
  echo "Error: Unknown hostname '$HOSTNAME'. Expected hostname containing 'm4' or 'm2'."
  echo "Set CONFIG_NAME manually: CONFIG_NAME=m4-agent-1 $0"
  exit 1
fi

# Allow override
CONFIG_NAME="${CONFIG_NAME:-}"
CONFIG_FILE="$CONFIG_DIR/${CONFIG_NAME}.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  echo ""
  echo "Available configs:"
  ls "$CONFIG_DIR"/*.conf 2>/dev/null || echo "  None found in $CONFIG_DIR"
  echo ""
  echo "Generate configs first:"
  echo "  cd $FLEET_REPO/ansible && ./scripts/onboard-vpn-clients.sh"
  exit 1
fi

echo "→ Found config for: $CONFIG_NAME"
echo "→ Expected VPN IP: $EXPECTED_IP"
echo ""

# Import into AmneziaWG app
echo "→ Opening config in AmneziaWG app..."
open -a AmneziaWG "$CONFIG_FILE"

echo ""
echo "✅ Config imported into AmneziaWG app."
echo ""
echo "Next steps:"
echo "1. In AmneziaWG app: click 'Activate' to connect"
echo "2. Enable 'Connect on login' in app preferences"
echo "3. Verify: ping 10.66.66.1 (VPN server)"
echo "4. Verify: curl -k https://vikunja.axinova-internal.xyz/api/v1/info"
