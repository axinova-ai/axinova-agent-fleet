#!/usr/bin/env bash
# Verify all VPN clients are properly registered
# Usage: ./verify-vpn-clients.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_FILE="$ANSIBLE_DIR/inventories/vpn/clients.yml"
SSH_HOST="sg-vpn"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✅${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC} $*"
}

log_error() {
    echo -e "${RED}❌${NC} $*"
}

check_prerequisites() {
    if ! command -v yq &> /dev/null; then
        log_error "yq not found. Install with: brew install yq"
        exit 1
    fi

    if ! ssh -q "$SSH_HOST" exit 2>/dev/null; then
        log_error "Cannot connect to $SSH_HOST via SSH"
        exit 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
}

verify_server_reachable() {
    log_info "Checking server connectivity..."

    if ssh "$SSH_HOST" 'exit' 2>/dev/null; then
        log_success "Server is reachable"
    else
        log_error "Cannot connect to server"
        return 1
    fi
}

verify_amneziawg_running() {
    log_info "Checking AmneziaWG service..."

    if ssh "$SSH_HOST" 'sudo systemctl is-active awg-quick@awg0' &>/dev/null; then
        log_success "AmneziaWG service is active"
    else
        log_error "AmneziaWG service is not running"
        return 1
    fi
}

verify_peer_count() {
    log_info "Verifying peer count..."

    local expected_count
    expected_count=$(yq e '.clients | length' "$INVENTORY_FILE")

    local actual_count
    actual_count=$(ssh "$SSH_HOST" 'sudo awg show awg0 peers 2>/dev/null | wc -l' | tr -d ' ')

    echo "  Expected: $expected_count clients"
    echo "  Registered: $actual_count peers"

    if [[ "$actual_count" -eq "$expected_count" ]]; then
        log_success "All clients registered"
    else
        log_error "Peer count mismatch"
        return 1
    fi
}

verify_no_duplicate_ips() {
    log_info "Checking for duplicate IP assignments..."

    local server_config
    server_config=$(ssh "$SSH_HOST" 'sudo cat /etc/amnezia/amneziawg/awg0.conf')

    local allowed_ips
    allowed_ips=$(echo "$server_config" | grep "AllowedIPs" | awk '{print $3}' | sort)

    local unique_ips
    unique_ips=$(echo "$allowed_ips" | uniq)

    if [[ "$allowed_ips" == "$unique_ips" ]]; then
        log_success "No duplicate IP assignments"
    else
        log_error "Duplicate IP addresses found in server config"
        return 1
    fi
}

verify_no_duplicate_pubkeys() {
    log_info "Checking for duplicate public keys..."

    local server_config
    server_config=$(ssh "$SSH_HOST" 'sudo cat /etc/amnezia/amneziawg/awg0.conf')

    local pubkeys
    pubkeys=$(echo "$server_config" | grep "PublicKey" | awk '{print $3}' | sort)

    local unique_keys
    unique_keys=$(echo "$pubkeys" | uniq)

    if [[ "$pubkeys" == "$unique_keys" ]]; then
        log_success "No duplicate public keys"
    else
        log_error "Duplicate public keys found in server config"
        return 1
    fi
}

verify_server_pubkey() {
    log_info "Verifying server public key..."

    local expected_pubkey
    expected_pubkey=$(yq e '.server.public_key' "$INVENTORY_FILE")

    local server_privkey
    server_privkey=$(ssh "$SSH_HOST" 'sudo cat /etc/wireguard/keys/server_private.key')

    local actual_pubkey
    actual_pubkey=$(echo "$server_privkey" | ssh "$SSH_HOST" 'wg pubkey')

    if [[ "$actual_pubkey" == "$expected_pubkey" ]]; then
        log_success "Server public key matches"
    else
        log_error "Server public key mismatch"
        echo "  Expected: $expected_pubkey"
        echo "  Actual: $actual_pubkey"
        return 1
    fi
}

verify_port_open() {
    log_info "Checking VPN port (54321/udp)..."

    local endpoint
    endpoint=$(yq e '.server.endpoint' "$INVENTORY_FILE")
    local server_ip
    server_ip=$(echo "$endpoint" | cut -d: -f1)
    local server_port
    server_port=$(echo "$endpoint" | cut -d: -f2)

    if nc -zu "$server_ip" "$server_port" 2>/dev/null; then
        log_success "Port ${server_port}/udp is reachable"
    else
        log_warning "Cannot verify UDP port ${server_port} (this is normal for UDP)"
    fi
}

check_connected_clients() {
    log_info "Checking connected clients..."

    local connected_count
    connected_count=$(ssh "$SSH_HOST" 'sudo awg show awg0 | grep -c "latest handshake" || true')

    local total_count
    total_count=$(yq e '.clients | length' "$INVENTORY_FILE")

    echo "  Connected: $connected_count / $total_count"

    if [[ "$connected_count" -eq 0 ]]; then
        log_warning "No clients currently connected (configs may not be distributed yet)"
    elif [[ "$connected_count" -lt "$total_count" ]]; then
        log_warning "Some clients not yet connected"
    else
        log_success "All clients connected"
    fi
}

verify_obfuscation_params() {
    log_info "Checking AmneziaWG obfuscation parameters..."

    local jc
    jc=$(ssh "$SSH_HOST" 'sudo awg show awg0 | grep "jc:" | awk "{print \$2}"')

    if [[ -n "$jc" ]] && [[ "$jc" -gt 0 ]]; then
        log_success "Obfuscation active (Jc=$jc)"
    else
        log_error "Obfuscation parameters not set"
        return 1
    fi
}

show_server_status() {
    log_info "Current server status:"
    echo ""
    ssh "$SSH_HOST" 'sudo awg show awg0'
    echo ""
}

print_summary() {
    echo ""
    echo "================================================"
    echo "Verification Summary"
    echo "================================================"
    echo ""

    local clients_json
    clients_json=$(yq e -o=json '.clients' "$INVENTORY_FILE")

    local count
    count=$(echo "$clients_json" | jq length)

    echo "Registered Clients:"
    for ((i=0; i<count; i++)); do
        local client_name
        local client_ip
        local device_type

        client_name=$(echo "$clients_json" | jq -r ".[$i].name")
        client_ip=$(echo "$clients_json" | jq -r ".[$i].ip")
        device_type=$(echo "$clients_json" | jq -r ".[$i].device_type")

        echo "  ✓ $client_name ($device_type) -> $client_ip"
    done

    echo ""
}

main() {
    echo "================================================"
    echo "VPN Client Verification (AmneziaWG)"
    echo "================================================"
    echo ""

    check_prerequisites

    local failed=0

    verify_server_reachable || ((failed++))
    verify_amneziawg_running || ((failed++))
    verify_peer_count || ((failed++))
    verify_no_duplicate_ips || ((failed++))
    verify_no_duplicate_pubkeys || ((failed++))
    verify_server_pubkey || ((failed++))
    verify_obfuscation_params || ((failed++))
    verify_port_open || true  # Don't fail on this
    check_connected_clients || true  # Don't fail on this
    show_server_status

    print_summary

    if [[ $failed -eq 0 ]]; then
        echo ""
        log_success "All verification checks passed!"
        exit 0
    else
        echo ""
        log_error "$failed verification check(s) failed"
        exit 1
    fi
}

main "$@"
