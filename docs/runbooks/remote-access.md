# Remote Access Runbook

How to access Mac minis remotely from your laptop.

## RustDesk (Recommended for Remote GUI)

RustDesk provides remote desktop access that works behind NAT, through VPNs, and without port forwarding. It's open source and can be self-hosted.

### Network Map

| Machine | RustDesk ID | VPN IP (AmneziaWG) | LAN IP |
|---------|-------------|---------------------|--------|
| M4 Mac mini (Agent1) | *(see RustDesk app)* | `10.66.66.3` | `192.168.3.6` / `m4-mini.local` |
| M2 Pro Mac mini (Agent2) | *(see RustDesk app)* | `10.66.66.2` | `192.168.3.5` / `m2-mini.local` |

### Connecting via RustDesk

1. Open RustDesk on your MacBook
2. Enter the target machine's RustDesk ID
3. Enter the permanent password (configured during setup)
4. You're in — full GUI control

RustDesk works from anywhere, regardless of which network you're on.

### RustDesk Setup (One-Time)

**On each Mac mini** (already done by `setup-remote-access.sh`):
1. Install: `brew install --cask rustdesk`
2. Grant Accessibility + Screen Recording permissions in System Settings > Privacy
3. Set a permanent password in RustDesk settings for unattended access
4. Note the RustDesk ID

**On your MacBook:**
```bash
brew install --cask rustdesk
```

### Self-Hosted Relay (Future Enhancement)

For lower latency and no dependency on RustDesk's public relay:
- Deploy RustDesk server (`hbbs` + `hbbr`) on the SG Aliyun VPS
- Configure clients to use your relay: RustDesk Settings > Network > ID/Relay Server
- This gives full infra control with no SaaS dependency

## SSH Access

### Prerequisites

- SSH keys set up on both minis
- VPN connected (if accessing over internet) or on same LAN
- `~/.ssh/config` configured

### Quick Access

```bash
# M4 Mac mini (Agent1)
ssh agent01

# M2 Pro Mac mini (Agent2)
ssh agent02
```

### MacBook SSH Config

Add to `~/.ssh/config`:

```
# Agent1 (M4 Mac mini) - VPN
Host agent01
  HostName 10.66.66.3
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent1 - LAN
Host agent01-lan
  HostName m4-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent2 (M2 Pro Mac mini) - VPN
Host agent02
  HostName 10.66.66.2
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent2 - LAN
Host agent02-lan
  HostName m2-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60
```

### First-Time Setup

**On your laptop:**

```bash
# Generate SSH key if not exists
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -C "your-email@example.com"
fi
```

**Copy SSH key to minis:**

```bash
# Via LAN (if on same network)
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@m4-mini.local
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@m2-mini.local

# Via VPN
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@10.66.66.3
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@10.66.66.2
```

### Troubleshooting

**Connection refused:**
- Check if Mac mini is powered on
- Try all paths: `ping 10.66.66.3`, `ping m4-mini.local`
- For GUI troubleshooting: use RustDesk

**Permission denied:**
- Verify SSH key is correct: `ssh-add -l`
- Check authorized_keys on mini: `cat ~/.ssh/authorized_keys`
- Password auth is intentionally disabled — use key auth only

**Timeout:**
- Check firewall rules on mini
- Verify Thunderbolt bridge is up (if using 10.10.10.x)

## Mosh (Mobile Shell)

For unstable connections (Wi-Fi roaming, laptop sleep):

```bash
# Install mosh
brew install mosh

# Connect via mosh
mosh agent01
mosh agent02
```

Mosh benefits:
- Survives connection drops (laptop sleep, network change)
- Lower latency for interactive typing
- Predictive local echo

## Screen Sharing (VNC)

For graphical tasks on LAN or VPN (as alternative to RustDesk):

```bash
# Via VPN
open vnc://10.66.66.3
open vnc://10.66.66.2

# Via LAN
open vnc://m4-mini.local
open vnc://m2-mini.local
```

Screen Sharing is restricted to `axinova-agent` and admin users. An HDMI dummy plug is recommended for full-resolution headless operation.

## VPN Access (AmneziaWG)

SSH over the VPN when away from home LAN:

```bash
# Connect to VPN first
cd ~/axinova/axinova-agent-fleet/bootstrap/vpn
./connect-sg.sh

# Verify connectivity
ping 10.66.66.3  # Agent1
ping 10.66.66.2  # Agent2

# Then SSH as normal
ssh agent01
```

## Thunderbolt Bridge (High-Speed Direct Connection)

If both minis are physically next to each other:

**Setup (one-time):**
1. Connect Thunderbolt cable between minis
2. System Settings > Network > Thunderbolt Bridge
3. Configure IPv4 manually:
   - M4 (Agent1): `10.10.10.2/24`
   - M2 Pro (Agent2): `10.10.10.1/24`

**Usage:**

```bash
# From Agent1 to Agent2
ssh axinova-agent@10.10.10.1

# From Agent2 to Agent1
ssh axinova-agent@10.10.10.2

# Fast file transfer (multi-Gbps)
rsync -avz --progress /local/path/ axinova-agent@10.10.10.1:/remote/path/
```

## Port Forwarding

To access services running on Mac mini from your laptop:

```bash
# Forward Portainer on agent01 to laptop port 9000
ssh -L 9000:localhost:9000 agent01

# Then access in browser: http://localhost:9000
```

Common ports:
- 9000: Portainer
- 11434: Ollama
- 5432: PostgreSQL

## Emergency Access (Physical)

If all remote access fails:

1. Physical access to Mac mini
2. Connect monitor, keyboard, mouse
3. Login as `axinova-agent` (or your admin user)
4. Check logs: `tail -f /var/log/system.log`
5. Restart services:
   ```bash
   # Restart SSH
   sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
   sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

   # Restart RustDesk
   open -a RustDesk

   # Restart VPN
   # Open AmneziaWG app and reconnect
   ```

## Security Best Practices

- **Never** share SSH private keys
- Use SSH key passphrase for extra security
- Password authentication is disabled on all minis (enforced by `setup-remote-access.sh`)
- Regularly review `~/.ssh/authorized_keys` for unexpected keys
- Monitor login attempts: `tail -f /var/log/system.log | grep ssh`
- Screen Sharing restricted to specific users via `dseditgroup`
- RustDesk: use strong permanent passwords, consider self-hosted relay

## Quick Reference

| Access Method | Use Case | Speed | Reliability | Works Remote? |
|---------------|----------|-------|-------------|---------------|
| RustDesk | Remote GUI (anywhere) | Good | Very High | Yes |
| VPN SSH | Remote CLI access | Fast | High | Yes |
| LAN SSH | Same-network CLI | Fast | High | No |
| VNC | GUI via VPN/LAN | Moderate | High | Via VPN |
| Mosh | Unstable connections | Fast | Very High | Via VPN |
| Thunderbolt | Large file transfers | Very Fast | High | No (direct cable) |

## Automation Scripts

Quick access scripts in `axinova-agent-fleet/scripts/`:

```bash
# SSH to agents (auto-detects: VPN → LAN)
./scripts/ssh-to-agent1.sh
./scripts/ssh-to-agent2.sh

# Check fleet status (includes RustDesk)
./scripts/fleet-status.sh
```
