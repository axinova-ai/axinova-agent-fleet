#!/usr/bin/env bash
set -euo pipefail

# Quick SSH to Agent2 (M2 Pro Mac mini)

# Try VPN IP first, fallback to .local
if ping -c 1 -W 1 10.100.0.11 &>/dev/null; then
  echo "→ Connecting via VPN (10.100.0.11)..."
  ssh axinova-agent@10.100.0.11
elif ping -c 1 -W 1 m2-mini.local &>/dev/null; then
  echo "→ Connecting via LAN (m2-mini.local)..."
  ssh axinova-agent@m2-mini.local
else
  echo "Error: Cannot reach Agent2"
  echo "Try:"
  echo "  1. Connect to VPN: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
  echo "  2. Check if Mac mini is powered on"
  echo "  3. Verify network: ping m2-mini.local"
  exit 1
fi
