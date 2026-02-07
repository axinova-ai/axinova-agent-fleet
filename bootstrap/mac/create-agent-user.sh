#!/usr/bin/env bash
set -euo pipefail

# Create axinova-agent user on macOS

USER_NAME="axinova-agent"
FULL_NAME="Axinova Agent"
USER_HOME="/Users/$USER_NAME"

echo "==> Creating user: $USER_NAME"

# Find next available UID (500+)
MAX_UID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
NEXT_UID=$((MAX_UID + 1))

# Create user
sudo dscl . -create /Users/$USER_NAME
sudo dscl . -create /Users/$USER_NAME UserShell /bin/zsh
sudo dscl . -create /Users/$USER_NAME RealName "$FULL_NAME"
sudo dscl . -create /Users/$USER_NAME UniqueID "$NEXT_UID"
sudo dscl . -create /Users/$USER_NAME PrimaryGroupID 20  # staff group
sudo dscl . -create /Users/$USER_NAME NFSHomeDirectory "$USER_HOME"

# Create home directory
sudo createhomedir -c -u "$USER_NAME" 2>/dev/null || true

# Set password (prompt)
echo "→ Set password for $USER_NAME:"
sudo dscl . -passwd /Users/$USER_NAME

# Add to admin group (optional, for Docker access)
# Uncomment if needed:
# sudo dscl . -append /Groups/admin GroupMembership $USER_NAME

echo "✅ User $USER_NAME created (UID: $NEXT_UID)"
echo "  Home: $USER_HOME"
echo "  Shell: /bin/zsh"
