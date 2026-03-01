# Remote Access Runbook

How to access Mac minis remotely from your laptop.

## Tailscale Access (Recommended for Remote)

Tailscale provides zero-config mesh networking between your MacBook and the Mac minis. Traffic goes P2P when possible, with DERP relay as fallback. No port forwarding needed.

### Tailscale Network Map

| Machine | Tailscale Hostname | MagicDNS Name | VPN IP (AmneziaWG) | LAN IP |
|---------|-------------------|---------------|---------------------|--------|
| M4 Mac mini (Agent1) | `agent01` | `agent01` | `10.66.66.3` | `192.168.3.6` / `m4-mini.local` |
| M2 Pro Mac mini (Agent2) | `focusagent02` | `focusagent02` | `10.66.66.2` | `192.168.3.5` / `m2-mini.local` |

### SSH via Tailscale

```bash
# Using MagicDNS hostname (simplest)
ssh axinova-agent@agent01
ssh axinova-agent@focusagent02

# Or using Tailscale IP
ssh axinova-agent@$(tailscale ip -4 agent01)
```

### Screen Sharing via Tailscale

```bash
open vnc://agent01
open vnc://focusagent02
```

Or in Finder: Go > Connect to Server > `vnc://agent01`

### MacBook SSH Config (Tailscale + VPN + LAN)

Add to `~/.ssh/config`:

```
# Agent1 (M4 Mac mini) - Tailscale
Host agent01
  HostName agent01
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent1 - VPN fallback
Host agent01-vpn
  HostName 10.66.66.3
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent1 - LAN fallback
Host agent01-lan
  HostName m4-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent2 (M2 Pro Mac mini) - Tailscale
Host focusagent02
  HostName focusagent02
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent2 - VPN fallback
Host focusagent02-vpn
  HostName 10.66.66.2
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

# Agent2 - LAN fallback
Host focusagent02-lan
  HostName m2-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60
```

### VPN Coexistence

Tailscale and AmneziaWG run simultaneously without conflict:
- **Tailscale** handles only `100.x.x.x` tailnet traffic (separate utun interface)
- **AmneziaWG** handles the default route for internet privacy
- No exit node is configured on Tailscale — it only provides mesh connectivity
- Both VPNs use separate utun interfaces and don't interfere

### Tailscale Troubleshooting

```bash
# Check Tailscale status
tailscale status

# Ping a peer (tests mesh connectivity)
tailscale ping agent01
tailscale ping focusagent02

# Get Tailscale IP for a peer
tailscale ip -4 agent01

# Re-authenticate
tailscale up

# Check which DERP relay is in use
tailscale netcheck

# Debug connectivity
tailscale ping --verbose agent01
```

## SSH Access

### Prerequisites

- SSH keys set up on both minis
- At least one network path available (Tailscale, VPN, or LAN)
- `~/.ssh/config` configured (see Tailscale section above)

### Quick Access

```bash
# M4 Mac mini (Agent1)
ssh agent01

# M2 Pro Mac mini (Agent2)
ssh focusagent02
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
# Via Tailscale (works from anywhere)
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@agent01
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@focusagent02

# Via LAN (if on same network)
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@m4-mini.local
ssh-copy-id -i ~/.ssh/id_ed25519.pub axinova-agent@m2-mini.local
```

### Troubleshooting

**Connection refused:**
- Check if Mac mini is powered on
- Try all paths: `tailscale ping agent01`, `ping 10.66.66.3`, `ping m4-mini.local`

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
mosh focusagent02
```

Mosh benefits:
- Survives connection drops (laptop sleep, network change)
- Lower latency for interactive typing
- Predictive local echo

## Screen Sharing (GUI)

For graphical tasks (Docker Desktop, browser testing):

```bash
# Via Tailscale (works from anywhere)
open vnc://agent01
open vnc://focusagent02

# Via VPN
open vnc://10.66.66.3
open vnc://10.66.66.2

# Via LAN
open vnc://m4-mini.local
open vnc://m2-mini.local
```

Or use macOS built-in Screen Sharing app:
1. Finder > Go > Connect to Server
2. Enter `vnc://agent01`

Screen Sharing is restricted to `axinova-agent` and admin users via `dseditgroup`. An HDMI dummy plug is recommended for full-resolution headless operation.

## VPN Access (AmneziaWG)

When Tailscale is unavailable:

```bash
# Connect to VPN first
cd ~/axinova/axinova-agent-fleet/bootstrap/vpn
./connect-sg.sh

# Verify connectivity
ping 10.66.66.3  # Agent1
ping 10.66.66.2  # Agent2

# Then SSH as normal
ssh agent01-vpn
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
scp large-file.tar.gz axinova-agent@10.10.10.1:/tmp/
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
   # Restart Tailscale
   open -a Tailscale

   # Restart SSH
   sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
   sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

   # Restart VPN
   # Open AmneziaWG app and reconnect
   ```

## Security Best Practices

- **Never** share SSH private keys
- Use SSH key passphrase for extra security
- Password authentication is disabled on all minis (enforced by `setup-tailscale.sh`)
- Regularly review `~/.ssh/authorized_keys` for unexpected keys
- Monitor login attempts: `tail -f /var/log/system.log | grep ssh`
- Screen Sharing restricted to specific users via `dseditgroup`

## Quick Reference

| Access Method | Use Case | Speed | Reliability | Works Remote? |
|---------------|----------|-------|-------------|---------------|
| Tailscale SSH | Default remote access | Fast | Very High | Yes |
| Tailscale VNC | Remote GUI access | Moderate | Very High | Yes |
| AmneziaWG SSH | Fallback remote access | Moderate | Moderate | Yes |
| LAN SSH | Same-network access | Fast | High | No |
| Mosh | Unstable connections | Fast | Very High | Yes |
| Thunderbolt | Large file transfers | Very Fast | High | No (direct cable) |

## Automation Scripts

Quick access scripts in `axinova-agent-fleet/scripts/`:

```bash
# SSH to agents (auto-detects best path: Tailscale → VPN → LAN)
./scripts/ssh-to-agent1.sh
./scripts/ssh-to-agent2.sh

# Check fleet status (includes Tailscale mesh)
./scripts/fleet-status.sh
```
