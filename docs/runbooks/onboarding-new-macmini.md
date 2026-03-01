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

## Step 4: Tailscale + Remote Access Hardening

```bash
cd ~/workspace/axinova-agent-fleet

# For M4 Mac mini (Agent1):
./bootstrap/mac/setup-tailscale.sh agent01

# For M2 Pro Mac mini (Agent2):
./bootstrap/mac/setup-tailscale.sh focusagent02
```

This script:
- Installs Tailscale and opens browser for login
- Sets MagicDNS hostname
- Enables and hardens SSH (key-only, password auth disabled)
- Enables Screen Sharing (restricted to `axinova-agent` + admin user)
- Configures headless power (no sleep, wake-on-LAN, auto-restart after power failure)

**Important:** Complete the Tailscale browser login when prompted. Both this mini and your MacBook must be on the same tailnet.

## Step 5: Deploy SSH Keys from MacBook

On your **MacBook** (not the Mac mini):

```bash
# Copy your SSH key to the new mini via Tailscale
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@agent01    # or focusagent02

# Verify key-based SSH works
ssh axinova-agent@agent01

# Verify password auth is rejected
ssh -o PasswordAuthentication=yes -o PubkeyAuthentication=no axinova-agent@agent01
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
# Tailscale SSH
ssh axinova-agent@agent01

# Tailscale Screen Sharing
open vnc://agent01

# VPN SSH (if VPN connected)
ssh axinova-agent@10.66.66.3   # agent01
ssh axinova-agent@10.66.66.2   # focusagent02

# LAN SSH (if on same network)
ssh axinova-agent@m4-mini.local

# Tailscale mesh ping
tailscale ping agent01
```

## Step 8: Update Fleet Inventory

After the new mini is online, update these files:

1. **SSH config** on your MacBook (`~/.ssh/config`):
   ```
   Host agent01
     HostName agent01
     User axinova-agent
     IdentityFile ~/.ssh/id_ed25519
     ForwardAgent yes
     ServerAliveInterval 60

   Host agent01-vpn
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
4. **Remote access runbook** (`docs/runbooks/remote-access.md`) — update IP tables

## Verification Checklist

Run through this checklist after completing all steps:

- [ ] `tailscale status` shows the new mini as online
- [ ] `tailscale ping <hostname>` succeeds from MacBook
- [ ] `ssh axinova-agent@<hostname>` works (key-based)
- [ ] `ssh -o PasswordAuthentication=yes axinova-agent@<hostname>` is rejected
- [ ] `open vnc://<hostname>` connects to Screen Sharing
- [ ] VPN is connected: `ping 10.66.66.1`
- [ ] Docker is running: `ssh axinova-agent@<hostname> docker ps`
- [ ] Power settings correct: `ssh axinova-agent@<hostname> pmset -g`
- [ ] Machine survives reboot and comes back online (Tailscale auto-starts)
- [ ] HDMI dummy plug provides usable Screen Sharing resolution
- [ ] Thunderbolt bridge is up (if applicable): `ping 10.10.10.x`

## Troubleshooting

**Tailscale not connecting:**
- Ensure Tailscale.app is running (check menu bar icon)
- Check status: `tailscale status`
- Re-authenticate: `tailscale up --hostname=<hostname>`

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
