#!/usr/bin/env bash
set -euo pipefail

# Quick SSH to Agent1 (M4 Mac mini)

# Try VPN IP first, fallback to .local
if ping -c 1 -W 1 10.100.0.10 &>/dev/null; then
  echo "→ Connecting via VPN (10.100.0.10)..."
  ssh axinova-agent@10.100.0.10
elif ping -c 1 -W 1 m4-mini.local &>/dev/null; then
  echo "→ Connecting via LAN (m4-mini.local)..."
  ssh axinova-agent@m4-mini.local
else
  echo "Error: Cannot reach Agent1"
  echo "Try:"
  echo "  1. Connect to VPN: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
  echo "  2. Check if Mac mini is powered on"
  echo "  3. Verify network: ping m4-mini.local"
  exit 1
fi
