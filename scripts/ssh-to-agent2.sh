#!/usr/bin/env bash
set -euo pipefail

# Quick SSH to Agent2 (M2 Pro Mac mini)
# Priority: Tailscale → VPN → LAN

# Detect Tailscale CLI
TAILSCALE_CLI=""
if command -v tailscale &>/dev/null; then
  TAILSCALE_CLI="tailscale"
elif [[ -x "/Applications/Tailscale.app/Contents/MacOS/Tailscale" ]]; then
  TAILSCALE_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

# Try Tailscale first
if [[ -n "$TAILSCALE_CLI" ]]; then
  TS_IP=$($TAILSCALE_CLI ip -4 focusagent02 2>/dev/null || true)
  if [[ -n "$TS_IP" ]] && ping -c 1 -W 1 "$TS_IP" &>/dev/null; then
    echo "→ Connecting via Tailscale ($TS_IP)..."
    exec ssh axinova-agent@"$TS_IP" "$@"
  fi
fi

# Try VPN
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
echo "  1. Check Tailscale: tailscale status"
echo "  2. Connect to VPN: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
echo "  3. Check if Mac mini is powered on"
echo "  4. Verify network: ping m2-mini.local"
exit 1
