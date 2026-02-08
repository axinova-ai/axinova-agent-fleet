#!/usr/bin/env bash
# Batch onboard all VPN clients from inventory
# Usage: ./onboard-vpn-clients.sh [--force-regenerate]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_FILE="$ANSIBLE_DIR/inventories/vpn/clients.yml"
DEFAULTS_FILE="$ANSIBLE_DIR/roles/wireguard_server/defaults/main.yml"
OUTPUT_DIR="/tmp/vpn-onboarding-$(date +%Y%m%d-%H%M%S)"

# SSH configuration
SSH_HOST="sg-vpn"
SERVER_KEYS_DIR="/etc/wireguard/clients"

# Options
FORCE_REGENERATE=false
if [[ "${1:-}" == "--force-regenerate" ]]; then
    FORCE_REGENERATE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    log_info "Checking prerequisites..."

    local missing=()

    if ! command -v yq &> /dev/null; then
        missing+=("yq - Install with: brew install yq")
    fi

    if ! command -v qrencode &> /dev/null; then
        missing+=("qrencode - Install with: brew install qrencode")
    fi

    if ! command -v ansible-playbook &> /dev/null; then
        missing+=("ansible")
    fi

    if ! ssh -q "$SSH_HOST" exit 2>/dev/null; then
        log_error "Cannot connect to $SSH_HOST via SSH"
        exit 1
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi

    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

parse_client_inventory() {
    log_info "Parsing client inventory..."

    local count
    count=$(yq e '.clients | length' "$INVENTORY_FILE")

    log_success "Found $count clients in inventory"

    # Validate no duplicate IPs
    local ips
    ips=$(yq e '.clients[].ip' "$INVENTORY_FILE" | sort)
    local unique_ips
    unique_ips=$(echo "$ips" | uniq)

    if [[ "$ips" != "$unique_ips" ]]; then
        log_error "Duplicate IP addresses found in inventory"
        exit 1
    fi

    # Validate no duplicate names
    local names
    names=$(yq e '.clients[].name' "$INVENTORY_FILE" | sort)
    local unique_names
    unique_names=$(echo "$names" | uniq)

    if [[ "$names" != "$unique_names" ]]; then
        log_error "Duplicate client names found in inventory"
        exit 1
    fi

    log_success "Inventory validation passed"
}

generate_all_keys() {
    log_info "Generating keys on server..."

    # Create server keys directory if needed
    ssh "$SSH_HOST" "sudo mkdir -p $SERVER_KEYS_DIR && sudo chmod 700 $SERVER_KEYS_DIR"

    local clients
    clients=$(yq e '.clients[].name' "$INVENTORY_FILE")

    local generated=0
    local skipped=0

    while IFS= read -r client; do
        local client_dir="$SERVER_KEYS_DIR/$client"

        # Check if keys already exist
        if ssh "$SSH_HOST" "sudo test -f $client_dir/private.key" && [[ "$FORCE_REGENERATE" != "true" ]]; then
            log_warning "Keys exist for $client, skipping (use --force-regenerate to rotate)"
            ((skipped++))
        else
            log_info "Generating keys for $client..."

            ssh "$SSH_HOST" "sudo mkdir -p $client_dir && \
                             cd $client_dir && \
                             sudo wg genkey | sudo tee private.key | sudo wg pubkey | sudo tee public.key > /dev/null && \
                             sudo chmod 600 private.key && \
                             sudo chmod 644 public.key"

            ((generated++))
        fi
    done <<< "$clients"

    log_success "Generated $generated new key pairs, skipped $skipped existing"
}

fetch_keys_to_local() {
    log_info "Fetching keys to local directory..."

    mkdir -p "$OUTPUT_DIR/keys"

    local clients
    clients=$(yq e '.clients[].name' "$INVENTORY_FILE")

    while IFS= read -r client; do
        local local_dir="$OUTPUT_DIR/keys/$client"
        mkdir -p "$local_dir"

        # Fetch private and public keys
        ssh "$SSH_HOST" "sudo cat $SERVER_KEYS_DIR/$client/private.key" > "$local_dir/private.key"
        ssh "$SSH_HOST" "sudo cat $SERVER_KEYS_DIR/$client/public.key" > "$local_dir/public.key"

        # Set proper permissions
        chmod 600 "$local_dir/private.key"
        chmod 644 "$local_dir/public.key"

        log_success "Fetched keys for $client"
    done <<< "$clients"
}

generate_client_configs() {
    log_info "Generating client configuration files..."

    mkdir -p "$OUTPUT_DIR/configs"

    # Read server configuration
    local server_endpoint
    local server_pubkey
    local vpn_network
    local dns

    server_endpoint=$(yq e '.server.endpoint' "$INVENTORY_FILE")
    server_pubkey=$(yq e '.server.public_key' "$INVENTORY_FILE")
    vpn_network=$(yq e '.server.vpn_network' "$INVENTORY_FILE")
    dns=$(yq e '.server.dns' "$INVENTORY_FILE")

    local clients_json
    clients_json=$(yq e -o=json '.clients' "$INVENTORY_FILE")

    local count
    count=$(echo "$clients_json" | jq length)

    for ((i=0; i<count; i++)); do
        local client_name
        local client_ip

        client_name=$(echo "$clients_json" | jq -r ".[$i].name")
        client_ip=$(echo "$clients_json" | jq -r ".[$i].ip")

        local private_key
        private_key=$(cat "$OUTPUT_DIR/keys/$client_name/private.key")

        local config_file="$OUTPUT_DIR/configs/$client_name.conf"

        cat > "$config_file" << EOF
[Interface]
PrivateKey = $private_key
Address = $client_ip/32
DNS = $dns

[Peer]
PublicKey = $server_pubkey
Endpoint = $server_endpoint
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

        chmod 600 "$config_file"
        log_success "Generated config for $client_name"
    done
}

generate_qr_codes() {
    log_info "Generating QR codes for mobile devices..."

    mkdir -p "$OUTPUT_DIR/qr-codes"

    local clients_json
    clients_json=$(yq e -o=json '.clients' "$INVENTORY_FILE")

    local count
    count=$(echo "$clients_json" | jq length)

    local qr_count=0

    for ((i=0; i<count; i++)); do
        local client_name
        local generate_qr

        client_name=$(echo "$clients_json" | jq -r ".[$i].name")
        generate_qr=$(echo "$clients_json" | jq -r ".[$i].generate_qr // false")

        if [[ "$generate_qr" == "true" ]]; then
            local config_content
            config_content=$(cat "$OUTPUT_DIR/configs/$client_name.conf")

            # Generate QR code image
            echo "$config_content" | qrencode -t PNG -o "$OUTPUT_DIR/qr-codes/$client_name.png"

            # Save as text for terminal display
            echo "$config_content" | qrencode -t ANSIUTF8 > "$OUTPUT_DIR/qr-codes/$client_name.txt"

            log_success "Generated QR code for $client_name"
            ((qr_count++))
        fi
    done

    log_success "Generated $qr_count QR codes"
}

update_ansible_vars() {
    log_info "Updating Ansible variables..."

    # Create backup
    local backup_file="$DEFAULTS_FILE.backup-$(date +%s)"
    cp "$DEFAULTS_FILE" "$backup_file"
    log_info "Created backup: $backup_file"

    # Read current file to preserve other variables
    local temp_file
    temp_file=$(mktemp)
    cp "$DEFAULTS_FILE" "$temp_file"

    # Clear existing client_ips and client pubkeys
    yq eval -i 'del(.client_ips)' "$temp_file"
    yq eval -i '. |= with_entries(select(.key | test("_pubkey$") | not))' "$temp_file"

    # Add new client_ips dictionary
    yq eval -i '.client_ips = {}' "$temp_file"

    # Add all clients from inventory
    local clients_json
    clients_json=$(yq e -o=json '.clients' "$INVENTORY_FILE")

    local count
    count=$(echo "$clients_json" | jq length)

    for ((i=0; i<count; i++)); do
        local client_name
        local client_ip

        client_name=$(echo "$clients_json" | jq -r ".[$i].name")
        client_ip=$(echo "$clients_json" | jq -r ".[$i].ip")

        # Convert hyphens to underscores for YAML keys
        local safe_name
        safe_name=$(echo "$client_name" | tr '-' '_')

        # Add to client_ips
        yq eval -i ".client_ips.${safe_name} = \"$client_ip\"" "$temp_file"

        # Add public key variable
        local pubkey
        pubkey=$(cat "$OUTPUT_DIR/keys/$client_name/public.key")
        yq eval -i ".${safe_name}_pubkey = \"$pubkey\"" "$temp_file"

        log_success "Added $client_name to Ansible vars"
    done

    # Move temp file to defaults
    mv "$temp_file" "$DEFAULTS_FILE"

    log_success "Ansible variables updated"
}

deploy_server_config() {
    log_info "Deploying server configuration via Ansible..."

    cd "$ANSIBLE_DIR"

    if ./scripts/setup-vpn.sh; then
        log_success "Server configuration deployed"
    else
        log_error "Ansible deployment failed"
        exit 1
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."

    local output_file="$OUTPUT_DIR/verification-results.txt"

    {
        echo "VPN Client Onboarding Verification"
        echo "=================================="
        echo "Timestamp: $(date)"
        echo ""

        # Get server status
        echo "Server Status:"
        ssh "$SSH_HOST" 'sudo wg show wg0'
        echo ""

        # Count peers
        local peer_count
        peer_count=$(ssh "$SSH_HOST" 'sudo wg show wg0 peers' | wc -l)

        echo "Registered Peers: $peer_count"

        # Expected count
        local expected_count
        expected_count=$(yq e '.clients | length' "$INVENTORY_FILE")

        echo "Expected Peers: $expected_count"

        if [[ "$peer_count" -eq "$expected_count" ]]; then
            echo "✅ All clients registered successfully"
        else
            echo "⚠️  Peer count mismatch"
        fi

    } | tee "$output_file"

    log_success "Verification complete"
}

organize_outputs() {
    log_info "Organizing outputs for distribution..."

    mkdir -p "$OUTPUT_DIR/distribution"/{macos,windows,ios,android}

    local clients_json
    clients_json=$(yq e -o=json '.clients' "$INVENTORY_FILE")

    local count
    count=$(echo "$clients_json" | jq length)

    for ((i=0; i<count; i++)); do
        local client_name
        local device_type

        client_name=$(echo "$clients_json" | jq -r ".[$i].name")
        device_type=$(echo "$clients_json" | jq -r ".[$i].device_type")

        case "$device_type" in
            macos|windows)
                ln -sf "../../configs/$client_name.conf" "$OUTPUT_DIR/distribution/$device_type/"
                ;;
            ios|android)
                if [[ -f "$OUTPUT_DIR/qr-codes/$client_name.png" ]]; then
                    ln -sf "../../qr-codes/$client_name.png" "$OUTPUT_DIR/distribution/$device_type/"
                    ln -sf "../../qr-codes/$client_name.txt" "$OUTPUT_DIR/distribution/$device_type/"
                fi
                ln -sf "../../configs/$client_name.conf" "$OUTPUT_DIR/distribution/$device_type/"
                ;;
        esac
    done

    log_success "Outputs organized by device type"
}

print_distribution_guide() {
    local report_file="$OUTPUT_DIR/onboarding-report.txt"

    {
        echo "================================================"
        echo "VPN Client Onboarding Complete"
        echo "================================================"
        echo ""
        echo "Output Directory: $OUTPUT_DIR"
        echo ""
        echo "Distribution Guide:"
        echo ""
        echo "macOS Devices:"
        echo "  1. SCP config file to device"
        echo "  2. sudo mv <config> /etc/wireguard/wg0.conf"
        echo "  3. sudo chmod 600 /etc/wireguard/wg0.conf"
        echo "  4. sudo wg-quick up wg0"
        echo ""
        echo "Windows Devices:"
        echo "  1. Copy config file to device"
        echo "  2. Open WireGuard GUI application"
        echo "  3. Import tunnel from file"
        echo "  4. Click 'Activate'"
        echo ""
        echo "Mobile Devices (iOS/Android):"
        echo "  1. Display QR code: cat $OUTPUT_DIR/qr-codes/<device>.txt"
        echo "  2. Or open PNG: $OUTPUT_DIR/qr-codes/<device>.png"
        echo "  3. Scan with WireGuard app"
        echo ""
        echo "Verification:"
        echo "  - From client: ping 10.66.66.1"
        echo "  - Check public IP: curl ifconfig.me (should show 8.222.187.10)"
        echo "  - Server status: ssh sg-vpn 'sudo wg show wg0'"
        echo ""
        echo "Security Reminder:"
        echo "  ⚠️  Delete temporary directory after distribution:"
        echo "     rm -rf $OUTPUT_DIR"
        echo ""

        echo "Client Summary:"
        yq e '.clients[] | "  - " + .name + " (" + .device_type + ") -> " + .ip' "$INVENTORY_FILE"

    } | tee "$report_file"
}

main() {
    echo "================================================"
    echo "VPN Client Batch Onboarding"
    echo "================================================"
    echo ""

    check_prerequisites
    parse_client_inventory
    generate_all_keys
    fetch_keys_to_local
    generate_client_configs
    generate_qr_codes
    update_ansible_vars
    deploy_server_config
    verify_deployment
    organize_outputs
    print_distribution_guide

    echo ""
    log_success "Onboarding complete! See $OUTPUT_DIR for all outputs"
}

main "$@"
