#!/usr/bin/env bash
set -eo pipefail

# verify_status.sh — Check current power settings against server-mode expectations
# Compatible with macOS bash 3.2

echo "==> Mac Mini Power Status Check"
echo ""

# --- Read current pmset values ---
pmset_custom=$(pmset -g custom)
pmset_global=$(pmset -g)

get_pmset_value() {
    local key="$1"
    local val

    # Special case: disablesleep is shown as SleepDisabled in pmset -g
    if [ "$key" = "disablesleep" ]; then
        val=$(echo "$pmset_global" | grep -E "SleepDisabled" | awk '{print $2}' | head -1 || true)
        echo "$val"
        return
    fi

    # Try pmset -g custom first, then pmset -g
    val=$(echo "$pmset_custom" | grep -E "^[[:space:]]+$key[[:space:]]+" | awk '{print $2}' | head -1 || true)
    if [ -z "$val" ]; then
        val=$(echo "$pmset_global" | grep -E "^[[:space:]]+$key[[:space:]]+" | awk '{print $2}' | head -1 || true)
    fi
    echo "$val"
}

# --- Check each setting ---
pass_count=0
fail_count=0
warn_count=0
total=0

printf "  %-40s %-10s %-10s %s\n" "Setting" "Current" "Expected" "Status"
printf "  %-40s %-10s %-10s %s\n" "-------" "-------" "--------" "------"

check_setting() {
    local key="$1"
    local expected="$2"
    local desc="$3"
    local current
    current=$(get_pmset_value "$key")
    total=$((total + 1))
    local status

    if [ -z "$current" ]; then
        if [ "$key" = "networkoversleep" ] || [ "$key" = "proximitywake" ]; then
            status="WARN"
            current="n/a"
            warn_count=$((warn_count + 1))
        else
            status="FAIL"
            current="n/a"
            fail_count=$((fail_count + 1))
        fi
    elif [ "$current" = "$expected" ]; then
        status="OK"
        pass_count=$((pass_count + 1))
    else
        if [ "$key" = "displaysleep" ]; then
            status="WARN"
            warn_count=$((warn_count + 1))
        else
            status="FAIL"
            fail_count=$((fail_count + 1))
        fi
    fi

    printf "  %-40s %-10s %-10s %s\n" "$desc ($key)" "$current" "$expected" "$status"
}

check_setting sleep          0 "System sleep"
check_setting disablesleep   1 "Sleep disabled"
check_setting displaysleep  10 "Display sleep (minutes)"
check_setting womp           1 "Wake on LAN"
check_setting autorestart    1 "Auto-restart on power failure"
check_setting networkoversleep 1 "Network over sleep (macOS 14+)"
check_setting tcpkeepalive   1 "TCP keepalive"
check_setting powernap       0 "Power Nap (should be off)"
check_setting proximitywake  0 "Proximity wake (should be off)"

echo ""

# --- Backup status ---
echo "==> Backup Status"
backup_dir="$HOME/.config/axinova"
backup_file=$(find "$backup_dir" -name 'pmset-backup-*.txt' 2>/dev/null | sort | head -1 || true)
if [ -n "$backup_file" ]; then
    echo "  Baseline backup: $backup_file"
else
    echo "  No baseline backup found."
fi
echo ""

# --- Overall result ---
echo "==> Result: $pass_count/$total PASS, $fail_count FAIL, $warn_count WARN"

if [ $fail_count -eq 0 ] && [ $warn_count -eq 0 ]; then
    echo "  PASS — All server-mode settings are active."
elif [ $fail_count -eq 0 ]; then
    echo "  PASS (with warnings) — Server mode is active."
else
    echo "  FAIL — Server mode is NOT fully active. Run server_mode_on.sh to fix."
fi
