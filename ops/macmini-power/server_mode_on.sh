#!/usr/bin/env bash
set -eo pipefail

# server_mode_on.sh — Apply 24/7 headless server power settings via pmset
# Compatible with macOS bash 3.2. Safe to run multiple times (idempotent).

DISPLAY_MINUTES=10
DRY_RUN=false
BACKUP_DIR="$HOME/.config/axinova"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --display-minutes)
            DISPLAY_MINUTES="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--display-minutes N]"
            exit 1
            ;;
    esac
done

echo "==> Mac Mini Server Mode: ON"
echo ""

if $DRY_RUN; then
    echo "    (dry-run mode — no changes will be applied)"
    echo ""
fi

# --- Backup current settings (only if no backup exists yet) ---
echo "==> Checking for existing baseline backup"

existing_backup=$(find "$BACKUP_DIR" -name 'pmset-backup-*.txt' 2>/dev/null | head -1 || true)

if [ -n "$existing_backup" ]; then
    echo "→ Baseline backup already exists: $existing_backup"
    echo "  Skipping backup to preserve original pre-server-mode state."
else
    backup_file="$BACKUP_DIR/pmset-backup-$(date +%Y%m%d-%H%M%S).txt"
    if $DRY_RUN; then
        echo "→ Would save current pmset settings to: $backup_file"
    else
        mkdir -p "$BACKUP_DIR"
        pmset -g custom > "$backup_file"
        echo "→ Saved current pmset settings to: $backup_file"
    fi
fi
echo ""

# --- Require sudo (unless dry-run) ---
if ! $DRY_RUN; then
    echo "==> Requesting sudo access"
    sudo -v
    echo ""
fi

# --- Apply settings ---
echo "==> Applying server-mode power settings"

apply_setting() {
    local key="$1"
    local value="$2"

    if $DRY_RUN; then
        echo "→ Would set $key = $value"
        return
    fi

    # networkoversleep is macOS 14+; silently ignore if unsupported
    if [ "$key" = "networkoversleep" ]; then
        if sudo pmset -a "$key" "$value" 2>/dev/null; then
            echo "→ Set $key = $value"
        else
            echo "→ WARN: $key not supported on this macOS version (requires 14+), skipped"
        fi
    else
        sudo pmset -a "$key" "$value"
        echo "→ Set $key = $value"
    fi
}

apply_setting sleep           0
apply_setting disablesleep    1
apply_setting displaysleep    "$DISPLAY_MINUTES"
apply_setting womp            1
apply_setting autorestart     1
apply_setting networkoversleep 1
apply_setting tcpkeepalive    1
apply_setting powernap        0
apply_setting proximitywake   0

echo ""

# --- Summary ---
echo "==> Summary"
if $DRY_RUN; then
    echo "  No changes applied (dry-run mode)."
    echo "  Remove --dry-run to apply settings."
else
    echo "  Server mode is ON. System will not sleep."
    echo "  Display sleeps after $DISPLAY_MINUTES minutes."
    echo "  Wake-on-LAN enabled, auto-restart on power failure enabled."
    echo ""
    echo "  Run verify_status.sh to confirm all settings."
fi
