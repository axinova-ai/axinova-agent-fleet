# Onboarding a New Mac Mini

End-to-end guide for adding a new Mac mini to the Axinova agent fleet, from bare metal to fully operational remote node.

## Prerequisites

- Physical access to the Mac mini
- Ethernet cable connected to home LAN router
- HDMI dummy plug (for full-resolution headless Screen Sharing)
- Thunderbolt cable (if connecting to another mini for high-speed bridge)
- Admin credentials for the fleet

## Step 1: Hardware Setup

1. Connect **ethernet** to the LAN router
2. Insert **HDMI dummy plug** into an HDMI port (enables full resolution for Screen Sharing without a real display)
3. Connect **Thunderbolt cable** to the other Mac mini (if applicable)
4. Connect power and boot the machine

## Step 2: macOS Setup Assistant

1. Select language and region
2. **Skip Apple ID** sign-in (choose "Set Up Later")
3. Create the initial admin account:
   - Full Name: use fleet naming convention (e.g. `Wei M4 Admin`, `Wei M2 Admin`)
   - Account Name: your personal admin username
   - Set a strong password
4. Complete remaining prompts (skip Siri, diagnostics, etc.)
5. Once at the desktop, open **System Settings > General > Software Update** and install any pending updates
6. Open **Terminal** (Applications > Utilities > Terminal)

## Step 3: Bootstrap macOS (Homebrew, Tools, Agent User)

Clone the fleet repo and run the bootstrap script:

```bash
# Install Xcode Command Line Tools (if not already present)
xcode-select --install

# Clone the fleet repo
git clone https://github.com/axinova-ai/axinova-agent-fleet.git ~/workspace/axinova-agent-fleet
cd ~/workspace/axinova-agent-fleet

# Run the bootstrap script
./bootstrap/mac/setup-macos.sh
```

This installs:
- Homebrew and all Brewfile dependencies
- Go toolchain and CLI tools (sqlc, migrate, govulncheck)
- Codex CLI (agent runtime) + Claude Code CLI (human review)
- Agent user with SSH keys and git identity
- Sudoers configuration
- Workspace directory structure

Follow the on-screen instructions to add the SSH public key to GitHub.

## Step 4: Remote Access Setup (RustDesk + SSH Hardening)

```bash
cd ~/workspace/axinova-agent-fleet
./bootstrap/mac/setup-remote-access.sh
```

This script:
- Installs RustDesk for remote desktop access
- Enables and hardens SSH (key-only, password auth disabled)
- Enables Screen Sharing / VNC (restricted to specific users)
- Configures headless power (no sleep, wake-on-LAN, auto-restart after power failure)

**Important after running:**
1. Grant RustDesk **Accessibility** and **Screen Recording** permissions in System Settings > Privacy
2. Set a **permanent password** in RustDesk settings for unattended access
3. Note the **RustDesk ID** — you'll need it to connect from your MacBook

## Step 5: Deploy SSH Keys from MacBook

On your **MacBook** (not the Mac mini):

```bash
# Copy your SSH key to the new mini via LAN
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@m4-mini.local    # or m2-mini.local

# Verify key-based SSH works
ssh axinova-agent@m4-mini.local

# Verify password auth is rejected
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no axinova-agent@m4-mini.local
# ^ Should fail with "Permission denied"
```

## Step 6: VPN Setup (AmneziaWG)

```bash
# On the Mac mini
cd ~/workspace/axinova-agent-fleet/bootstrap/vpn
./amneziawg-setup.sh
```

Import the client config for this machine from `vpn-distribution/configs/`. Verify VPN connectivity:

```bash
ping 10.66.66.1  # VPN server (Singapore)
```

## Step 7: Disconnect Monitor and Verify Remote Access

1. Disconnect the physical monitor/keyboard/mouse (leave the HDMI dummy plug)
2. From your MacBook, verify all access methods:

```bash
# RustDesk (works from anywhere)
# Open RustDesk app, enter the mini's ID + password

# VPN SSH (if VPN connected)
ssh axinova-agent@10.66.66.3   # agent01
ssh axinova-agent@10.66.66.2   # focusagent02

# LAN SSH (if on same network)
ssh axinova-agent@m4-mini.local

# VNC (on LAN or VPN)
open vnc://m4-mini.local
```

## Step 8: Update Fleet Inventory

After the new mini is online, update these files:

1. **SSH config** on your MacBook (`~/.ssh/config`):
   ```
   Host agent01
     HostName 10.66.66.3
     User axinova-agent
     IdentityFile ~/.ssh/id_ed25519
     ForwardAgent yes
     ServerAliveInterval 60

   Host agent01-lan
     HostName m4-mini.local
     User axinova-agent
     IdentityFile ~/.ssh/id_ed25519
     ForwardAgent yes
     ServerAliveInterval 60
   ```

2. **VPN client inventory** (`ansible/inventories/vpn/clients.yml`) — add the new device
3. **Fleet status script** (`scripts/fleet-status.sh`) — add LAN IP if changed
4. **Remote access runbook** (`docs/runbooks/remote-access.md`) — update IP/RustDesk ID tables

## Verification Checklist

Run through this checklist after completing all steps:

- [ ] RustDesk connects from MacBook (enter ID + password)
- [ ] `ssh axinova-agent@<LAN-IP>` works (key-based)
- [ ] `ssh -o PasswordAuthentication=yes axinova-agent@<LAN-IP>` is rejected
- [ ] VNC connects: `open vnc://<LAN-IP>`
- [ ] VPN is connected: `ping 10.66.66.1`
- [ ] SSH over VPN works: `ssh axinova-agent@<VPN-IP>`
- [ ] Docker is running: `ssh axinova-agent@<IP> docker ps`
- [ ] Power settings correct: `ssh axinova-agent@<IP> pmset -g`
- [ ] Machine survives reboot and comes back online
- [ ] RustDesk auto-starts after reboot
- [ ] HDMI dummy plug provides usable resolution
- [ ] Thunderbolt bridge is up (if applicable): `ping 10.10.10.x`

## Troubleshooting

**RustDesk shows "Permission denied" or black screen:**
- Grant Accessibility + Screen Recording permissions in System Settings > Privacy
- Restart RustDesk after granting permissions

**RustDesk connection fails:**
- Verify RustDesk is running on the mini: `pgrep -x RustDesk`
- Check the permanent password is set
- Check internet connectivity (RustDesk needs relay access)

**Screen Sharing shows tiny/black screen:**
- Verify HDMI dummy plug is inserted
- Check resolution: System Settings > Displays

**SSH connection refused after reboot:**
- Verify Remote Login is enabled: `sudo systemsetup -getremotelogin`
- Check sshd is loaded: `sudo launchctl list | grep ssh`

**Mac mini not waking from sleep:**
- Verify power settings: `pmset -g`
- Ensure `sleep 0` and `disablesleep 1` are set
- Check Wake on LAN: `pmset -g | grep womp` (should be 1)
