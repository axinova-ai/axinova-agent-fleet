#!/usr/bin/env bash
set -euo pipefail

# Generate AmneziaWG client config and QR code for mobile devices
# Usage: ./generate-client-qr.sh <client-name> <client-ip>

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <client-name> <client-ip>"
    echo "Example: $0 android 10.66.66.6"
    exit 1
fi

CLIENT_NAME="$1"
CLIENT_IP="$2"
SERVER_ENDPOINT="8.222.187.10:54321"

# AmneziaWG obfuscation parameters
AWG_JC=5
AWG_JMIN=50
AWG_JMAX=1000
AWG_S1=45
AWG_S2=75
AWG_H1=1009484
AWG_H2=2147444
AWG_H3=3088611
AWG_H4=4166003

# Check for qrencode
if ! command -v qrencode &> /dev/null; then
    echo "Error: qrencode is not installed"
    echo "Install with: brew install qrencode (macOS) or apt install qrencode (Linux)"
    exit 1
fi

# Generate client keys
echo "Generating keys for client: $CLIENT_NAME"
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

echo ""
echo "Client: $CLIENT_NAME"
echo "Client IP: $CLIENT_IP"
echo "Private Key: $PRIVATE_KEY"
echo "Public Key: $PUBLIC_KEY"
echo ""

# Prompt for server public key
echo "Enter server public key (from: ssh sg-vpn 'cat /etc/wireguard/keys/server_public.key'):"
read -r SERVER_PUBLIC_KEY

# Generate client config with AmneziaWG obfuscation
CLIENT_CONFIG="[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_IP/32
DNS = 1.1.1.1
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25"

echo ""
echo "=== Client Configuration (AmneziaWG) ==="
echo "$CLIENT_CONFIG"
echo ""

# Save to file
CONFIG_FILE="${CLIENT_NAME}_awg0.conf"
echo "$CLIENT_CONFIG" > "$CONFIG_FILE"
echo "Saved to: $CONFIG_FILE"

# Generate QR code
QR_FILE="${CLIENT_NAME}_qr.png"
echo "$CLIENT_CONFIG" | qrencode -o "$QR_FILE"
echo "QR code saved to: $QR_FILE"

# Display QR in terminal
echo ""
echo "=== QR Code (scan with AmneziaWG mobile app) ==="
echo "$CLIENT_CONFIG" | qrencode -t ansiutf8

echo ""
echo "=== IMPORTANT: Add this peer to server config ==="
echo ""
echo "1. Update ansible/roles/wireguard_server/defaults/main.yml:"
echo "   ${CLIENT_NAME}_pubkey: \"$PUBLIC_KEY\""
echo ""
echo "2. Re-run: ansible/scripts/setup-vpn.sh"
echo ""
echo "3. Or manually add to server /etc/amnezia/amneziawg/awg0.conf:"
echo "[Peer] # $CLIENT_NAME"
echo "PublicKey = $PUBLIC_KEY"
echo "AllowedIPs = $CLIENT_IP/32"
echo ""
echo "Then restart: ssh sg-vpn 'awg-quick down awg0 && awg-quick up awg0'"
echo ""
echo "IMPORTANT: Client must use AmneziaWG app (NOT WireGuard)"
echo "  iOS:     https://apps.apple.com/us/app/amneziawg/id6478942365"
echo "  Android: AmneziaWG on Google Play"
echo ""
