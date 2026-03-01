#!/usr/bin/env bash
set -euo pipefail

# Quick SSH to Agent1 (M4 Mac mini)
# Priority: VPN → LAN

# Try VPN first
if ping -c 1 -W 1 10.66.66.3 &>/dev/null; then
  echo "→ Connecting via VPN (10.66.66.3)..."
  exec ssh axinova-agent@10.66.66.3 "$@"
fi

# Try LAN
if ping -c 1 -W 1 m4-mini.local &>/dev/null; then
  echo "→ Connecting via LAN (m4-mini.local)..."
  exec ssh axinova-agent@m4-mini.local "$@"
fi

echo "Error: Cannot reach Agent1"
echo "Try:"
echo "  1. Connect to VPN: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
echo "  2. Check if Mac mini is powered on"
echo "  3. Verify network: ping m4-mini.local"
echo "  4. For GUI access: use RustDesk"
exit 1
