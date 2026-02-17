#!/usr/bin/env bash
# Interactive helper for distributing VPN client configurations
# Usage: ./distribute-client-configs.sh <onboarding-output-dir>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}$*${NC}"
}

if [[ $# -ne 1 ]]; then
    log_error "Usage: $0 <onboarding-output-dir>"
    echo "Example: $0 /tmp/vpn-onboarding-20260208-143022"
    exit 1
fi

OUTPUT_DIR="$1"

if [[ ! -d "$OUTPUT_DIR" ]]; then
    log_error "Directory not found: $OUTPUT_DIR"
    exit 1
fi

CONFIGS_DIR="$OUTPUT_DIR/configs"
QR_CODES_DIR="$OUTPUT_DIR/qr-codes"
DISTRIBUTION_DIR="$OUTPUT_DIR/distribution"

# Check if directories exist
for dir in "$CONFIGS_DIR" "$DISTRIBUTION_DIR"; do
    if [[ ! -d "$dir" ]]; then
        log_error "Required directory not found: $dir"
        exit 1
    fi
done

show_main_menu() {
    echo ""
    print_header "================================================"
    print_header "VPN Client Configuration Distribution"
    print_header "================================================"
    echo ""
    echo "Available clients:"
    echo ""

    local i=1
    for config in "$CONFIGS_DIR"/*.conf; do
        local client_name
        client_name=$(basename "$config" .conf)

        local has_qr=""
        if [[ -f "$QR_CODES_DIR/$client_name.png" ]]; then
            has_qr=" [QR Available]"
        fi

        echo "  $i) $client_name$has_qr"
        ((i++))
    done

    echo ""
    echo "  q) Quit"
    echo ""
}

show_client_menu() {
    local client_name="$1"
    local config_file="$CONFIGS_DIR/$client_name.conf"
    local qr_file="$QR_CODES_DIR/$client_name.png"
    local qr_txt_file="$QR_CODES_DIR/$client_name.txt"

    while true; do
        echo ""
        print_header "Client: $client_name"
        echo ""
        echo "Distribution options:"
        echo ""
        echo "  1) Show configuration file content"
        echo "  2) Copy config path to clipboard"

        if [[ -f "$qr_txt_file" ]]; then
            echo "  3) Display QR code in terminal"
            echo "  4) Open QR code image"
        fi

        echo "  5) Show distribution instructions"
        echo "  b) Back to main menu"
        echo ""
        echo -n "Select option: "
        read -r choice

        case "$choice" in
            1)
                echo ""
                print_header "Configuration for $client_name:"
                echo ""
                cat "$config_file"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                if command -v pbcopy &> /dev/null; then
                    echo -n "$config_file" | pbcopy
                    log_success "Config path copied to clipboard: $config_file"
                else
                    echo "Config path: $config_file"
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                if [[ -f "$qr_txt_file" ]]; then
                    echo ""
                    print_header "QR Code for $client_name:"
                    echo ""
                    cat "$qr_txt_file"
                    echo ""
                    log_info "Scan with AmneziaWG mobile app"
                    read -p "Press Enter to continue..."
                else
                    log_error "QR code not available for this client"
                fi
                ;;
            4)
                if [[ -f "$qr_file" ]]; then
                    if command -v open &> /dev/null; then
                        open "$qr_file"
                        log_success "Opened QR code image"
                    else
                        echo "QR code path: $qr_file"
                    fi
                    read -p "Press Enter to continue..."
                else
                    log_error "QR code image not available for this client"
                fi
                ;;
            5)
                show_distribution_instructions "$client_name" "$config_file"
                read -p "Press Enter to continue..."
                ;;
            b|B)
                break
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
    done
}

show_distribution_instructions() {
    local client_name="$1"
    local config_file="$2"

    echo ""
    print_header "Distribution Instructions for $client_name"
    echo ""

    # Determine device type from distribution directory
    local device_type=""
    for type_dir in "$DISTRIBUTION_DIR"/*; do
        if [[ -L "$type_dir/$client_name.conf" ]] || [[ -L "$type_dir/$client_name.png" ]]; then
            device_type=$(basename "$type_dir")
            break
        fi
    done

    case "$device_type" in
        macos)
            echo "macOS Distribution:"
            echo ""
            echo "1. Install AmneziaWG app from:"
            echo "   https://github.com/amnezia-vpn/amneziawg-apple/releases"
            echo ""
            echo "2. Import config file via AmneziaWG app"
            echo "   Or manually:"
            echo "   scp '$config_file' $client_name:~/Downloads/"
            echo "   ssh $client_name"
            echo "   sudo mkdir -p /etc/amnezia/amneziawg"
            echo "   sudo mv ~/Downloads/$client_name.conf /etc/amnezia/amneziawg/awg0.conf"
            echo "   sudo chmod 600 /etc/amnezia/amneziawg/awg0.conf"
            echo ""
            echo "3. Start VPN:"
            echo "   sudo awg-quick up awg0"
            echo ""
            echo "4. Verify connection:"
            echo "   ping 10.66.66.1"
            echo "   curl ifconfig.me  # Should show 8.222.187.10"
            ;;
        windows)
            echo "Windows Distribution:"
            echo ""
            echo "1. Copy config file to Windows device via:"
            echo "   - Shared network folder"
            echo "   - USB drive"
            echo "   - Email (less secure)"
            echo ""
            echo "2. Install AmneziaWG for Windows from:"
            echo "   https://github.com/amnezia-vpn/amneziawg-windows/releases"
            echo ""
            echo "3. Import configuration:"
            echo "   - Open AmneziaWG GUI application"
            echo "   - Click 'Add Tunnel' -> 'Import tunnel(s) from file'"
            echo "   - Select $client_name.conf"
            echo ""
            echo "4. Activate tunnel:"
            echo "   - Click 'Activate' button"
            echo ""
            echo "5. Verify connection:"
            echo "   - Open browser and visit: http://ifconfig.me"
            echo "   - Should show 8.222.187.10"
            ;;
        ios|android)
            echo "Mobile Distribution:"
            echo ""
            echo "1. Install AmneziaWG app:"
            if [[ "$device_type" == "ios" ]]; then
                echo "   - iOS: https://apps.apple.com/us/app/amneziawg/id6478942365"
            else
                echo "   - Android: AmneziaWG on Google Play"
            fi
            echo ""
            echo "2. Option A - QR Code (Easiest):"
            echo "   - Display QR code: cat '$QR_CODES_DIR/$client_name.txt'"
            echo "   - Or open image: open '$QR_CODES_DIR/$client_name.png'"
            echo "   - In app: Tap '+' -> 'Create from QR code'"
            echo "   - Scan the QR code"
            echo ""
            echo "3. Option B - Manual Import:"
            echo "   - Transfer $client_name.conf to device"
            echo "   - In app: Tap '+' -> 'Create from file or archive'"
            echo "   - Select the config file"
            echo ""
            echo "4. Activate tunnel:"
            echo "   - Toggle the switch to connect"
            echo ""
            echo "5. Verify connection:"
            echo "   - Open browser: http://ifconfig.me"
            echo "   - Should show 8.222.187.10"
            ;;
        *)
            echo "Config file: $config_file"
            echo ""
            echo "Generic instructions:"
            echo "1. Copy config to target device"
            echo "2. Install WireGuard client"
            echo "3. Import configuration"
            echo "4. Activate VPN connection"
            ;;
    esac

    echo ""
    log_warning "Security: Delete config file from device after importing!"
    echo ""
}

main() {
    while true; do
        show_main_menu
        echo -n "Select client (1-n or q): "
        read -r choice

        if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
            echo ""
            log_info "Exiting distribution helper"
            break
        fi

        # Get list of configs as array
        local configs=()
        while IFS= read -r -d '' config; do
            configs+=("$config")
        done < <(find "$CONFIGS_DIR" -name "*.conf" -print0 | sort -z)

        # Validate choice is a number and in range
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#configs[@]}" ]]; then
            local selected_config="${configs[$((choice-1))]}"
            local client_name
            client_name=$(basename "$selected_config" .conf)
            show_client_menu "$client_name"
        else
            log_error "Invalid selection"
        fi
    done
}

main
