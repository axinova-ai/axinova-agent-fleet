#!/usr/bin/env bash
set -euo pipefail

# Quick connect to Aliyun Singapore VPN

echo "==> Connecting to Aliyun SG VPN..."

# Check if config exists
if [[ ! -f /etc/wireguard/wg0.conf ]]; then
  echo "Error: /etc/wireguard/wg0.conf not found"
  echo "Run: ./wireguard-install.sh first"
  exit 1
fi

# Check if already connected
if sudo wg show wg0 &>/dev/null; then
  echo "Already connected to VPN"
  sudo wg show wg0
  exit 0
fi

# Connect
sudo wg-quick up wg0

echo ""
echo "✅ Connected to VPN"
echo ""
echo "Verifying connectivity..."
if ping -c 3 10.100.0.1 &>/dev/null; then
  echo "✅ Can reach Aliyun SG server (10.100.0.1)"
else
  echo "⚠️  Cannot reach server, check config"
fi

echo ""
echo "To disconnect: sudo wg-quick down wg0"
