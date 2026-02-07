# Remote Access Runbook

How to access Mac minis remotely from your laptop.

## SSH Access

### Prerequisites

- SSH keys set up on both minis
- VPN connected (if accessing over internet)
- `~/.ssh/config` configured

### Quick Access

```bash
# M4 Mac mini (Agent1)
ssh agent1

# M2 Pro Mac mini (Agent2)
ssh agent2
```

### First-Time Setup

**On your laptop:**

```bash
# Generate SSH key if not exists
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  ssh-keygen -t ed25519 -C "your-email@example.com"
fi

# Add to ~/.ssh/config
cat >> ~/.ssh/config <<EOF

Host agent1
  HostName m4-mini.local  # Or use VPN IP: 10.100.0.10
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

Host agent2
  HostName m2-mini.local  # Or use VPN IP: 10.100.0.11
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60
EOF
```

**Copy SSH key to minis:**

```bash
# M4 mini
ssh-copy-id -i ~/.ssh/id_ed25519.pub your-initial-user@m4-mini.local

# M2 Pro mini
ssh-copy-id -i ~/.ssh/id_ed25519.pub your-initial-user@m2-mini.local
```

### Troubleshooting

**Connection refused:**
- Check if Mac mini is powered on
- Verify VPN is connected: `ping 10.100.0.10`
- Try LAN access: `ssh axinova-agent@192.168.1.x`

**Permission denied:**
- Verify SSH key is correct: `ssh-add -l`
- Check authorized_keys on mini: `cat ~/.ssh/authorized_keys`

**Timeout:**
- Check firewall rules on mini
- Verify Thunderbolt bridge is up (if using 169.254.x.x)

## Mosh (Mobile Shell)

For unstable connections (Wi-Fi roaming, laptop sleep):

```bash
# Install mosh
brew install mosh

# Connect via mosh
mosh agent1
mosh agent2
```

Mosh benefits:
- Survives connection drops (laptop sleep, network change)
- Lower latency for interactive typing
- Predictive local echo

## Screen Sharing (GUI)

For graphical tasks (Docker Desktop, browser testing):

**On Mac mini:**
1. System Settings → Sharing
2. Enable "Screen Sharing"
3. Set "Allow access for: Only these users" → add `axinova-agent`

**On your laptop:**

```bash
# Open Screen Sharing
open vnc://agent1.local
open vnc://10.100.0.10  # Via VPN
```

Or use macOS built-in Screen Sharing app:
1. Finder → Go → Network
2. Find Mac mini
3. Click "Screen Sharing"

## VPN Access

When accessing minis from outside LAN:

```bash
# Connect to VPN first
cd ~/axinova/axinova-agent-fleet/bootstrap/vpn
./connect-sg.sh

# Verify connectivity
ping 10.100.0.10  # Agent1
ping 10.100.0.11  # Agent2

# Then SSH as normal
ssh agent1
```

## Thunderbolt Bridge (High-Speed Direct Connection)

If both minis are physically next to each other:

**Setup (one-time):**
1. Connect Thunderbolt cable between minis
2. System Settings → Network → Thunderbolt Bridge
3. Configure IPv4 manually:
   - M4 (Agent1): `169.254.100.1/24`
   - M2 Pro (Agent2): `169.254.100.2/24`

**Usage:**

```bash
# From Agent1 to Agent2
ssh axinova-agent@169.254.100.2

# From Agent2 to Agent1
ssh axinova-agent@169.254.100.1

# Fast file transfer (multi-Gbps)
scp large-file.tar.gz axinova-agent@169.254.100.2:/tmp/
rsync -avz --progress /local/path/ axinova-agent@169.254.100.2:/remote/path/
```

## Port Forwarding

To access services running on Mac mini from your laptop:

```bash
# Forward Portainer on agent1 to laptop port 9000
ssh -L 9000:localhost:9000 agent1

# Then access in browser: http://localhost:9000
```

Common ports:
- 9000: Portainer
- 11434: Ollama
- 5432: PostgreSQL

## Emergency Access (Physical)

If SSH/VPN fails:

1. Physical access to Mac mini
2. Connect monitor, keyboard, mouse
3. Login as `axinova-agent` (or your admin user)
4. Check logs: `tail -f /var/log/system.log`
5. Restart services:
   ```bash
   sudo wg-quick down wg0 && sudo wg-quick up wg0  # VPN
   sudo systemctl restart sshd  # SSH (if applicable)
   ```

## Security Best Practices

- **Never** share SSH private keys
- Use SSH key passphrase for extra security
- Disable password authentication: `sudo sed -i.bak 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config`
- Regularly review `~/.ssh/authorized_keys` for unexpected keys
- Monitor login attempts: `tail -f /var/log/system.log | grep ssh`

## Quick Reference

| Access Method | Use Case | Speed | Reliability |
|---------------|----------|-------|-------------|
| SSH | Command-line tasks | Fast | High |
| Mosh | Unstable connections | Fast | Very High |
| Screen Sharing | GUI tasks | Moderate | High |
| Thunderbolt | Large file transfers | Very Fast | High (LAN only) |
| VPN | Remote access | Moderate | Moderate |

## Automation Scripts

Quick access scripts in `axinova-agent-fleet/scripts/`:

```bash
# SSH to agents
./scripts/ssh-to-agent1.sh
./scripts/ssh-to-agent2.sh

# Check fleet status
./scripts/fleet-status.sh
```
