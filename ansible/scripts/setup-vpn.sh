#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}=== AmneziaWG VPN Server Setup ===${NC}"
echo ""

# Check if Ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Error: Ansible is not installed${NC}"
    echo "Install with: brew install ansible"
    exit 1
fi

# Check if inventory exists
if [[ ! -f "$ANSIBLE_DIR/inventories/vpn/hosts.ini" ]]; then
    echo -e "${RED}Error: Inventory file not found${NC}"
    echo "Expected: $ANSIBLE_DIR/inventories/vpn/hosts.ini"
    exit 1
fi

# Check SSH connectivity
echo -e "${YELLOW}Checking SSH connectivity to sg-vpn...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes sg-vpn 'echo "SSH OK"' &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to sg-vpn via SSH${NC}"
    echo "Please ensure:"
    echo "  1. SSH config entry exists for sg-vpn in ~/.ssh/config"
    echo "  2. SSH key is configured and authorized"
    echo "  3. Host is reachable: ssh sg-vpn"
    exit 1
fi
echo -e "${GREEN}SSH connectivity OK${NC}"
echo ""

# Run Ansible playbook
echo -e "${YELLOW}Running Ansible playbook...${NC}"
cd "$ANSIBLE_DIR"

ansible-playbook \
    -i inventories/vpn/hosts.ini \
    playbooks/vpn_server.yml \
    "$@"

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Next steps:"
echo "  1. SSH to server and get the public key:"
echo "     ssh sg-vpn 'cat /etc/wireguard/keys/server_public.key'"
echo ""
echo "  2. Configure clients with AmneziaWG app (NOT WireGuard)"
echo "     See: docs/vpn/CLIENT_SETUP.md"
echo ""
echo "  3. After generating client keys, update defaults/main.yml with client public keys"
echo "     Then re-run this script to update server config"
echo ""
echo "  4. Verify server status:"
echo "     ssh sg-vpn 'awg show awg0'"
echo ""
