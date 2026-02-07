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
    CLIENT_IP="10.100.0.10"
  elif [[ "$HOSTNAME" == *"m2"* ]]; then
    CLIENT_IP="10.100.0.11"
  else
    CLIENT_IP="10.100.0.20"  # Laptop or other
  fi

  sudo tee "$WG_CONFIG" > /dev/null <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_IP/24

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <ALIYUN_SG_PUBLIC_IP>:51820
AllowedIPs = 10.100.0.0/24
PersistentKeepalive = 25
EOF

  echo "✅ Config created at $WG_CONFIG"
  echo ""
  echo "⚠️  Edit $WG_CONFIG and replace:"
  echo "  - <SERVER_PUBLIC_KEY> with Aliyun SG server's public key"
  echo "  - <ALIYUN_SG_PUBLIC_IP> with server's public IP"
  echo ""
else
  echo "→ WireGuard config already exists at $WG_CONFIG"
fi

echo "Next steps:"
echo "1. Edit $WG_CONFIG with server details"
echo "2. Connect: sudo wg-quick up wg0"
echo "3. Verify: ping 10.100.0.1"
echo "4. Auto-connect on boot: sudo brew services start wireguard-tools"
