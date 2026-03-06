#!/usr/bin/env bash
# rotate-vpn-port.sh — Change VPN server port and update all client configs
# Usage: ./scripts/rotate-vpn-port.sh <new_port>
# Example: ./scripts/rotate-vpn-port.sh 13231
#
# Does everything in one command:
#   1. Updates server awg0.conf + UFW
#   2. Restarts amneziawg-go
#   3. Updates all client config files in this repo
#   4. Prints QR codes for phones in your terminal
#   5. Commits and pushes to git

set -euo pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPN_SERVER="root@8.222.187.10"
SERVER_CONF="/etc/amnezia/amneziawg/awg0.conf"

NEW_PORT="${1:-}"
if [[ -z "$NEW_PORT" ]]; then
  echo "Usage: $0 <new_port>"
  echo "Example: $0 13231"
  exit 1
fi

# Detect current port from any client config
OLD_PORT=$(grep "Endpoint" "$FLEET_DIR/vpn-distribution/configs/macos/m4-agent-1.conf" \
  | grep -oE ':[0-9]+$' | tr -d ':')

if [[ -z "$OLD_PORT" ]]; then
  echo "ERROR: could not detect current port from client configs"
  exit 1
fi

if [[ "$OLD_PORT" == "$NEW_PORT" ]]; then
  echo "Port is already $NEW_PORT — nothing to do."
  exit 0
fi

echo "==> Rotating VPN port: $OLD_PORT → $NEW_PORT"
echo ""

# --- Step 1: Update server ---
echo "→ [1/5] Updating server config and UFW..."
ssh "$VPN_SERVER" "
  sed -i 's/ListenPort = ${OLD_PORT}/ListenPort = ${NEW_PORT}/' ${SERVER_CONF}
  systemctl restart awg-quick@awg0
  # Kill any stale amneziawg-go on old port
  sleep 2
  OLD_PID=\$(ss -unlp | grep ':${OLD_PORT}' | grep -oP 'pid=\K[0-9]+' | head -1)
  [[ -n \"\$OLD_PID\" ]] && kill \"\$OLD_PID\" 2>/dev/null || true
  # Update UFW
  ufw allow ${NEW_PORT}/udp comment 'AmneziaWG VPN' 2>/dev/null
  ufw delete allow ${OLD_PORT}/udp 2>/dev/null || true
  ufw reload 2>/dev/null
  echo \"Server now listening on port ${NEW_PORT}:\"
  ss -unlp | grep amnezia | grep ':${NEW_PORT}'
"
echo "  Server updated."

# --- Step 2: Update all client config files ---
echo ""
echo "→ [2/5] Updating client config files..."
find "$FLEET_DIR/vpn-distribution/configs/" -name "*.conf" \
  -exec sed -i '' "s/:${OLD_PORT}/:${NEW_PORT}/g" {} \;
find "$FLEET_DIR/ansible/" -type f \( -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
  -exec sed -i '' "s/${OLD_PORT}/${NEW_PORT}/g" {} \;
echo "  All config files updated."

# --- Step 3: QR codes for phones ---
echo ""
echo "→ [3/5] Generating phone QR codes (scan these now)..."

if ! command -v qrencode &>/dev/null; then
  echo "  qrencode not installed. Install: brew install qrencode"
  echo "  Config files updated — import manually."
else
  QR_DEVICES=(
    "wei-iphone:ios/wei-iphone.conf"
    "wei-android:android/wei-android-xiaomi-ultra14.conf"
    "lisha-iphone:ios/lisha-iphone.conf"
  )
  for entry in "${QR_DEVICES[@]}"; do
    name="${entry%%:*}"
    path="${entry##*:}"
    conf="$FLEET_DIR/vpn-distribution/configs/$path"
    if [[ -f "$conf" ]]; then
      echo ""
      echo "  ┌─── $name (port $NEW_PORT) ───"
      qrencode -t ansiutf8 < "$conf"
      echo "  └────────────────────────────────"
    fi
  done
fi

# --- Step 4: Commit and push ---
echo ""
echo "→ [4/5] Committing to git..."
cd "$FLEET_DIR"
git add vpn-distribution/configs/ ansible/
git commit -m "[vpn] Rotate port ${OLD_PORT} → ${NEW_PORT} (GFW block)"
git push
echo "  Pushed."

# --- Step 5: Summary ---
echo ""
echo "→ [5/5] Done. Summary:"
echo ""
echo "  Server:    listening on UDP ${NEW_PORT}"
echo "  Configs:   all updated + pushed to git"
echo "  Mac Minis: run 'git pull' then re-import VPN config in AmneziaWG app"
echo "  Phones:    scan QR codes above"
echo ""
echo "  Next time GFW blocks the port, run:"
echo "    ./scripts/rotate-vpn-port.sh <new_port>"
echo ""
echo "  Aliyun console: remember to open UDP ${NEW_PORT} in the security group"
echo "  → https://swas.console.aliyun.com"
