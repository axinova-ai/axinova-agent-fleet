#!/usr/bin/env bash
set -eo pipefail

# server_mode_off.sh — Restore macOS default power settings (or saved baseline)
# Compatible with macOS bash 3.2.

DRY_RUN=false
BACKUP_DIR="$HOME/.config/axinova"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run]"
            exit 1
            ;;
    esac
done

echo "==> Mac Mini Server Mode: OFF"
echo ""

if $DRY_RUN; then
    echo "    (dry-run mode — no changes will be applied)"
    echo ""
fi

# --- Check for backup ---
echo "==> Checking for baseline backup"

backup_file=$(find "$BACKUP_DIR" -name 'pmset-backup-*.txt' 2>/dev/null | sort | head -1 || true)

restore_from_backup=false
if [ -n "$backup_file" ]; then
    echo "→ Found baseline backup: $backup_file"
    echo ""
    echo "  Restore from this backup? (Settings will be parsed and re-applied.)"
    read -rp "  [y/N] " answer
    case "$answer" in
        y|Y) restore_from_backup=true ;;
    esac
    echo ""
fi

# --- Require sudo (unless dry-run) ---
if ! $DRY_RUN; then
    echo "==> Requesting sudo access"
    sudo -v
    echo ""
fi

if $restore_from_backup; then
    echo "==> Restoring settings from backup"
    echo ""

    while IFS= read -r line; do
        key=$(echo "$line" | grep -oE '^[[:space:]]+[a-zA-Z]+' | xargs)
        value=$(echo "$line" | grep -oE '[0-9]+$')
        if [ -n "$key" ] && [ -n "$value" ]; then
            if $DRY_RUN; then
                echo "→ Would restore $key = $value"
            else
                if sudo pmset -a "$key" "$value" 2>/dev/null; then
                    echo "→ Restored $key = $value"
                else
                    echo "→ WARN: Could not restore $key = $value (may not be supported)"
                fi
            fi
        fi
    done < "$backup_file"
else
    echo "==> Applying sensible macOS defaults"

    apply_default() {
        local key="$1"
        local value="$2"

        if $DRY_RUN; then
            echo "→ Would set $key = $value"
            return
        fi

        if [ "$key" = "networkoversleep" ]; then
            if sudo pmset -a "$key" "$value" 2>/dev/null; then
                echo "→ Set $key = $value"
            else
                echo "→ WARN: $key not supported on this macOS version, skipped"
            fi
        else
            sudo pmset -a "$key" "$value"
            echo "→ Set $key = $value"
        fi
    }

    apply_default sleep           1
    apply_default disablesleep    0
    apply_default displaysleep   10
    apply_default womp            1
    apply_default autorestart     0
    apply_default networkoversleep 0
    apply_default tcpkeepalive    1
    apply_default powernap        1
    apply_default proximitywake   1
fi
echo ""

# --- Summary ---
echo "==> Summary"
if $DRY_RUN; then
    echo "  No changes applied (dry-run mode)."
    echo "  Remove --dry-run to apply settings."
else
    echo "  Server mode is OFF. Normal power management restored."
    if $restore_from_backup; then
        echo "  Settings restored from: $backup_file"
    else
        echo "  Sensible macOS defaults applied."
    fi
    echo ""
    echo "  Run verify_status.sh to see current state."
fi
