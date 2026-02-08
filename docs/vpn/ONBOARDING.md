# VPN Client Onboarding Guide

This guide covers the automated batch provisioning workflow for onboarding VPN clients to the Axinova WireGuard VPN server.

## Overview

The onboarding automation provides:
- Batch provisioning for multiple clients simultaneously
- Server-side key generation (more secure than client-side)
- Automated Ansible variable updates (no manual YAML editing)
- QR code generation for mobile devices
- Organized output by device type
- Verification and validation checks

## Prerequisites

### Required Tools

```bash
# macOS installation
brew install yq qrencode

# Verify tools
yq --version
qrencode --version
ansible --version
```

### Server Access

Ensure SSH access to the VPN server is configured:
```bash
# Test connection
ssh sg-vpn 'echo "Connection OK"'
```

Your `~/.ssh/config` should have:
```
Host sg-vpn
    HostName 8.222.187.10
    User root
    IdentityFile ~/.ssh/axinova-sg-vpn
```

## Client Inventory

All clients are defined in a single source of truth: `ansible/inventories/vpn/clients.yml`

### Inventory Structure

```yaml
clients:
  - name: device-name          # Unique identifier (use hyphens)
    device_type: macos         # macos, windows, ios, android
    ip: 10.66.66.X            # VPN IP address (must be unique)
    description: "..."         # Human-readable description
    generate_qr: true          # Optional: generate QR code (mobile only)
```

### Adding a New Client

1. Edit `ansible/inventories/vpn/clients.yml`
2. Add new client entry with unique name and IP
3. Run the onboarding script (see below)

Example:
```yaml
  - name: new-device
    device_type: macos
    ip: 10.66.66.20
    description: "New MacBook Pro"
```

## Onboarding Workflow

### Step 1: Run Batch Onboarding

```bash
cd /Users/weixia/axinova/axinova-agent-fleet/ansible

# Onboard all clients from inventory
./scripts/onboard-vpn-clients.sh
```

The script will:
1. ✅ Parse client inventory (validate no duplicates)
2. ✅ Generate key pairs on server (skips existing)
3. ✅ Fetch keys to local temp directory
4. ✅ Generate client config files
5. ✅ Generate QR codes for mobile devices
6. ✅ Update Ansible variables automatically
7. ✅ Deploy server configuration via Ansible
8. ✅ Verify all peers registered
9. ✅ Organize outputs for distribution

**Output directory:** `/tmp/vpn-onboarding-YYYYMMDD-HHMMSS/`

### Step 2: Verify Deployment

```bash
# Automated verification
./scripts/verify-vpn-clients.sh

# Expected checks:
# ✅ Server reachable
# ✅ WireGuard service active
# ✅ All clients registered
# ✅ No duplicate IPs
# ✅ No duplicate public keys
# ✅ Server public key matches
```

### Step 3: Distribute Configurations

#### Interactive Helper

```bash
./scripts/distribute-client-configs.sh /tmp/vpn-onboarding-YYYYMMDD-HHMMSS/

# Provides:
# - Client menu selection
# - QR code display
# - Distribution instructions by device type
# - Config copying utilities
```

#### Manual Distribution by Device Type

**macOS Devices:**
```bash
# Copy config to device
scp /tmp/vpn-onboarding-*/configs/device-name.conf device-name:~/Downloads/

# Install on device
ssh device-name
sudo mkdir -p /etc/wireguard
sudo mv ~/Downloads/device-name.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# Start VPN
sudo wg-quick up wg0

# Enable at boot (optional)
sudo systemctl enable wg-quick@wg0
```

**Windows Devices:**
1. Copy `device-name.conf` to Windows device
2. Install WireGuard from https://www.wireguard.com/install/
3. Open WireGuard GUI
4. Click "Add Tunnel" → "Import tunnel(s) from file"
5. Select the config file
6. Click "Activate"

**Mobile Devices (iOS/Android):**
1. Install WireGuard app from App Store/Play Store
2. Display QR code:
   ```bash
   cat /tmp/vpn-onboarding-*/qr-codes/device-name.txt
   # Or open PNG:
   open /tmp/vpn-onboarding-*/qr-codes/device-name.png
   ```
3. In WireGuard app: Tap "+" → "Create from QR code"
4. Scan the QR code
5. Toggle switch to connect

### Step 4: Client Testing

From each client after configuration:

```bash
# Test VPN gateway
ping 10.66.66.1

# Verify public IP (should show Singapore server)
curl ifconfig.me
# Expected: 8.222.187.10

# Test DNS resolution
nslookup google.com
```

### Step 5: Final Verification

```bash
# Check server status
ssh sg-vpn 'sudo wg show wg0'

# Should show:
# - All peers listed
# - Recent handshake timestamps
# - RX/TX bytes for active connections

# Automated verification
./scripts/verify-vpn-clients.sh
# Expected: All checks pass, X/X clients connected
```

### Step 6: Cleanup

```bash
# After successful distribution, remove temporary files
rm -rf /tmp/vpn-onboarding-YYYYMMDD-HHMMSS/

# Server-side keys remain at: /etc/wireguard/clients/
# (kept for key rotation and backup purposes)
```

## Output Directory Structure

```
/tmp/vpn-onboarding-YYYYMMDD-HHMMSS/
├── keys/                          # Private/public key pairs
│   ├── device-name/
│   │   ├── private.key (600)      # ⚠️ SENSITIVE
│   │   └── public.key (644)
│   └── ...
├── configs/                       # Client configuration files
│   ├── device-name.conf (600)     # ⚠️ CONTAINS PRIVATE KEY
│   └── ...
├── qr-codes/                      # Mobile device QR codes
│   ├── device-name.png
│   ├── device-name.txt            # Terminal display
│   └── ...
├── distribution/                  # Organized by device type
│   ├── macos/
│   ├── windows/
│   ├── ios/
│   └── android/
├── onboarding-report.txt         # Summary report
└── verification-results.txt       # Verification output
```

## Security Considerations

### What Gets Committed to Git

**Safe to commit:**
- ✅ `clients.yml` inventory (device names, IPs, descriptions)
- ✅ Public keys (in `defaults/main.yml`)
- ✅ Scripts and templates
- ✅ Documentation

**NEVER commit:**
- ❌ Private keys
- ❌ Generated client configs (contain private keys)
- ❌ `/tmp/vpn-onboarding-*` directories
- ❌ Backup files (`*.backup-*`)

### Key Management

**Server-side storage:**
```
/etc/wireguard/clients/
├── device-name/
│   ├── private.key (600, root:root)
│   └── public.key (644, root:root)
```

**Local temporary storage:**
- Keys fetched to `/tmp/vpn-onboarding-*/` during onboarding
- Delete after distribution
- Never commit to git (.gitignore rules in place)

### Client Revocation

To revoke a client device:

1. Edit `ansible/inventories/vpn/clients.yml`
2. Remove or comment out the client entry
3. Re-run onboarding script:
   ```bash
   ./scripts/onboard-vpn-clients.sh
   ```

The script will regenerate the server config without that peer.

## Troubleshooting

### Keys Already Exist

If you see "Keys exist, skipping", the script is being idempotent and preserving existing keys.

To force key regeneration (rotation):
```bash
./scripts/onboard-vpn-clients.sh --force-regenerate
```

This will:
- Generate new key pairs for all clients
- Update server configuration
- Require redistribution of configs to all clients

### Connection Issues

**Client can't connect:**
```bash
# On server, check if peer is registered
ssh sg-vpn 'sudo wg show wg0'

# On client, check interface status
sudo wg show wg0

# Check firewall rules on server
ssh sg-vpn 'sudo iptables -L -n -v'
```

**No handshake appearing:**
- Verify correct server endpoint (8.222.187.10:51820)
- Check UDP port 51820 is not blocked by firewall
- Verify client config has correct server public key
- Check system time is synchronized (NTP)

### Verification Failures

```bash
# Re-run verification with details
./scripts/verify-vpn-clients.sh

# Check specific client registration
ssh sg-vpn 'sudo wg show wg0 dump' | grep <client-ip>

# Review server logs
ssh sg-vpn 'sudo journalctl -u wg-quick@wg0 -n 50'
```

## Advanced Operations

### Key Rotation

To rotate keys for a specific client:

1. Edit `clients.yml` (no changes needed)
2. On server, delete existing keys:
   ```bash
   ssh sg-vpn 'sudo rm -rf /etc/wireguard/clients/device-name'
   ```
3. Re-run onboarding script
4. Distribute new config to client

### Backup and Recovery

**Backup client keys:**
```bash
ssh sg-vpn 'sudo tar czf /root/wireguard-clients-backup.tar.gz /etc/wireguard/clients/'
scp sg-vpn:/root/wireguard-clients-backup.tar.gz ~/backups/
```

**Restore from backup:**
```bash
scp ~/backups/wireguard-clients-backup.tar.gz sg-vpn:/root/
ssh sg-vpn 'sudo tar xzf /root/wireguard-clients-backup.tar.gz -C /'
```

### Monitoring Connected Clients

```bash
# Show all connected clients
ssh sg-vpn 'sudo wg show wg0'

# Count active connections
ssh sg-vpn 'sudo wg show wg0 | grep -c "latest handshake"'

# Show bandwidth usage
ssh sg-vpn 'sudo wg show wg0 transfer'
```

## Architecture

### Automated Workflow

```
┌─────────────────────────────────────────────────────────┐
│ 1. clients.yml (Single Source of Truth)                │
│    - Device names, IPs, types                           │
│    - Version controlled                                 │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 2. onboard-vpn-clients.sh                              │
│    - Generate keys on server                            │
│    - Fetch keys locally                                 │
│    - Generate configs + QR codes                        │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Auto-update Ansible Variables                       │
│    - Update defaults/main.yml                           │
│    - Backup old configuration                           │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Deploy Server Config (Ansible)                      │
│    - Dynamic Jinja2 template                            │
│    - Iterate all clients from client_ips dict           │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Verification                                         │
│    - Peer count check                                   │
│    - No duplicate IPs/keys                              │
│    - Server reachability                                │
└─────────────────────────────────────────────────────────┘
```

### Benefits

1. **Single Source of Truth**: All clients defined in one YAML file
2. **No Manual YAML Editing**: Script updates Ansible variables automatically
3. **Idempotent**: Safe to re-run, skips existing keys
4. **Scalable**: Add new clients by editing one file
5. **Secure**: Server-side key generation, proper permissions
6. **Traceable**: Version-controlled inventory, backed up variables
7. **Validated**: Automated verification checks

## Reference

### Files

- `ansible/inventories/vpn/clients.yml` - Client inventory
- `ansible/scripts/onboard-vpn-clients.sh` - Main onboarding script
- `ansible/scripts/verify-vpn-clients.sh` - Verification script
- `ansible/scripts/distribute-client-configs.sh` - Distribution helper
- `ansible/roles/wireguard_server/templates/wg0.conf.j2` - Server config template
- `ansible/roles/wireguard_server/defaults/main.yml` - Ansible variables (auto-updated)

### Server Details

- **Endpoint**: 8.222.187.10:51820
- **VPN Network**: 10.66.66.0/24
- **Server IP**: 10.66.66.1
- **DNS**: 1.1.1.1
- **Server Public Key**: `4utg8R6pINVXmF0EilIQx2LAtndqO0plkv2kdEwf3QE=`

### IP Allocation Strategy

- `10.66.66.1` - VPN server
- `10.66.66.2-9` - Mac devices
- `10.66.66.10-19` - Mobile devices
- `10.66.66.20-29` - Windows devices
- `10.66.66.30+` - Reserved for future expansion

Non-sequential assignment allows for logical grouping and future additions.
