#!/usr/bin/env bash
# rotate-vpn-port.sh — Rotate VPN server's internal AWG listen port
# Usage: ./scripts/rotate-vpn-port.sh <new_internal_port>
# Example: ./scripts/rotate-vpn-port.sh 27845
#
# Architecture: Client configs NEVER change. They always point to the stable
# relay port (39999). This script only changes what's on the server side:
#   1. Updates awg0.conf ListenPort (the internal AWG port)
#   2. Updates the iptables DNAT rule: 39999 → <new_port>
#   3. Saves iptables rules persistently
#   4. Restarts AWG service
#   5. Updates UFW (allows new internal port, removes old)
#
# Client configs: NEVER need updating. Port 39999 is permanent.
# Aliyun security group: only 39999 needs to be open (already done).

set -euo pipefail

FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPN_SERVER="root@8.222.187.10"
SERVER_CONF="/etc/amnezia/amneziawg/awg0.conf"
STABLE_PORT="39999"

NEW_PORT="${1:-}"
if [[ -z "$NEW_PORT" ]]; then
  echo "Usage: $0 <new_internal_port>"
  echo "Example: $0 27845"
  echo ""
  echo "NOTE: Client configs always use port ${STABLE_PORT} (stable relay port)."
  echo "      This script only changes the internal AWG port on the server."
  exit 1
fi

# Detect current internal port from server config
OLD_PORT=$(ssh "$VPN_SERVER" "grep 'ListenPort' ${SERVER_CONF} | awk '{print \$3}'")

if [[ -z "$OLD_PORT" ]]; then
  echo "ERROR: could not detect current port from server config"
  exit 1
fi

if [[ "$OLD_PORT" == "$NEW_PORT" ]]; then
  echo "Port is already $NEW_PORT — nothing to do."
  exit 0
fi

echo "==> Rotating VPN internal port: $OLD_PORT → $NEW_PORT"
echo "    (Client configs stay on stable port ${STABLE_PORT} — no client changes needed)"
echo ""

# --- Step 1: Update server ---
echo "→ [1/4] Updating server config, DNAT rule, and UFW..."
ssh "$VPN_SERVER" "
  # Update awg0.conf
  sed -i 's/ListenPort = ${OLD_PORT}/ListenPort = ${NEW_PORT}/' ${SERVER_CONF}

  # Update iptables DNAT: remove old rule, add new rule
  iptables -t nat -D PREROUTING -p udp --dport ${STABLE_PORT} -j DNAT --to-destination :${OLD_PORT} 2>/dev/null || true
  iptables -t nat -A PREROUTING -p udp --dport ${STABLE_PORT} -j DNAT --to-destination :${NEW_PORT}

  # Persist iptables rules
  iptables-save > /etc/iptables/rules.v4

  # Restart AWG
  systemctl restart awg-quick@awg0
  sleep 2

  # Kill any stale amneziawg-go on old port
  OLD_PID=\$(ss -unlp 2>/dev/null | grep ':${OLD_PORT}' | grep -oP 'pid=\K[0-9]+' | head -1)
  [[ -n \"\$OLD_PID\" ]] && kill \"\$OLD_PID\" 2>/dev/null || true

  # Update UFW (internal ports — not strictly needed since clients use 39999)
  ufw allow ${NEW_PORT}/udp comment 'AmneziaWG internal port' 2>/dev/null
  ufw delete allow ${OLD_PORT}/udp 2>/dev/null || true
  ufw reload 2>/dev/null

  echo \"Server internal port: ${NEW_PORT} (relay via ${STABLE_PORT})\"
  ss -unlp | grep amnezia | grep ':${NEW_PORT}'
  echo \"DNAT rule:\"
  iptables -t nat -L PREROUTING -n | grep ${STABLE_PORT}
"
echo "  Server updated."

# --- Step 2: Update ansible references (docs only — not client configs) ---
echo ""
echo "→ [2/4] Updating ansible port references..."
find "$FLEET_DIR/ansible/" -type f \( -name "*.yml" -o -name "*.sh" -o -name "*.md" \) \
  -exec grep -l "$OLD_PORT" {} \; \
  | xargs -r sed -i '' "s/${OLD_PORT}/${NEW_PORT}/g"
echo "  Ansible files updated."

# --- Step 3: Commit ansible changes ---
echo ""
echo "→ [3/4] Committing to git..."
cd "$FLEET_DIR"
if git diff --quiet ansible/ 2>/dev/null; then
  echo "  No ansible changes to commit."
else
  git add ansible/
  git commit -m "[vpn] Rotate internal port ${OLD_PORT} → ${NEW_PORT} (stable relay: ${STABLE_PORT})"
  git push
  echo "  Pushed."
fi

# --- Step 4: Summary ---
echo ""
echo "→ [4/4] Done. Summary:"
echo ""
echo "  Client stable port:  UDP ${STABLE_PORT} (permanent — no client changes needed)"
echo "  Server internal AWG: UDP ${NEW_PORT}"
echo "  DNAT relay:          ${STABLE_PORT} → ${NEW_PORT}"
echo ""
echo "  Mac Minis: already have correct config (port ${STABLE_PORT}) — no action needed"
echo "  Phones:    already connected via port ${STABLE_PORT} — no action needed"
echo ""
echo "  Aliyun console: UDP ${STABLE_PORT} is already open — no changes needed"
echo "  → https://swas.console.aliyun.com"
echo ""
echo "  Next time GFW blocks, run:"
echo "    ./scripts/rotate-vpn-port.sh <any_random_port>"
