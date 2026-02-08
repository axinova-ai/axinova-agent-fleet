#!/usr/bin/env bash
set -euo pipefail

# Install and configure WireGuard for Aliyun Singapore VPN

echo "==> WireGuard VPN Setup"

# Check if WireGuard is installed
if ! command -v wg &>/dev/null; then
  echo "Error: WireGuard not installed. Run: brew install wireguard-tools"
  exit 1
fi

# Generate WireGuard keys if not exist
WG_DIR="$HOME/.config/wireguard"
mkdir -p "$WG_DIR"

if [[ ! -f "$WG_DIR/privatekey" ]]; then
  echo "→ Generating WireGuard keys..."
  wg genkey | tee "$WG_DIR/privatekey" | wg pubkey > "$WG_DIR/publickey"
  chmod 600 "$WG_DIR/privatekey"

  echo ""
  echo "✅ WireGuard keys generated"
  echo "Public key (share with server admin):"
  cat "$WG_DIR/publickey"
  echo ""
else
  echo "→ WireGuard keys already exist"
  echo "Public key:"
  cat "$WG_DIR/publickey"
  echo ""
fi

# Create config template
WG_CONFIG="/etc/wireguard/wg0.conf"
if [[ ! -f "$WG_CONFIG" ]]; then
  echo "→ Creating WireGuard config template..."

  PRIVATE_KEY=$(cat "$WG_DIR/privatekey")

  # Determine agent number based on hostname
  HOSTNAME=$(hostname -s)
  if [[ "$HOSTNAME" == *"m4"* ]]; then
    CLIENT_IP="10.66.66.2"   # mac-mini-1
  elif [[ "$HOSTNAME" == *"m2"* ]]; then
    CLIENT_IP="10.66.66.3"   # mac-mini-2
  else
    CLIENT_IP="10.66.66.7"   # Laptop or other
  fi

  sudo tee "$WG_CONFIG" > /dev/null <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = 8.222.187.10:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  echo "✅ Config created at $WG_CONFIG"
  echo ""
  echo "⚠️  Edit $WG_CONFIG and replace:"
  echo "  - <SERVER_PUBLIC_KEY> with server's public key"
  echo "    Get it with: ssh sg-vpn 'cat /etc/wireguard/keys/server_public.key'"
  echo ""
else
  echo "→ WireGuard config already exists at $WG_CONFIG"
fi

echo "Next steps:"
echo "1. Get server public key: ssh sg-vpn 'cat /etc/wireguard/keys/server_public.key'"
echo "2. Edit $WG_CONFIG and replace <SERVER_PUBLIC_KEY>"
echo "3. Add this client's public key to server (see docs/vpn/CLIENT_SETUP.md)"
echo "4. Connect: sudo wg-quick up wg0"
echo "5. Verify: ping 10.66.66.1"
echo "6. Auto-connect on boot: sudo brew services start wireguard-tools"
