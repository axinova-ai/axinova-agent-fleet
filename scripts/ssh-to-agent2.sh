#!/usr/bin/env bash
set -euo pipefail

# Quick SSH to Agent2 (M2 Pro Mac mini)
# Priority: VPN → LAN

# Try VPN first
if ping -c 1 -W 1 10.66.66.2 &>/dev/null; then
  echo "→ Connecting via VPN (10.66.66.2)..."
  exec ssh axinova-agent@10.66.66.2 "$@"
fi

# Try LAN
if ping -c 1 -W 1 m2-mini.local &>/dev/null; then
  echo "→ Connecting via LAN (m2-mini.local)..."
  exec ssh axinova-agent@m2-mini.local "$@"
fi

echo "Error: Cannot reach Agent2"
echo "Try:"
echo "  1. Connect to VPN: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
echo "  2. Check if Mac mini is powered on"
echo "  3. Verify network: ping m2-mini.local"
echo "  4. For GUI access: use RustDesk"
exit 1
