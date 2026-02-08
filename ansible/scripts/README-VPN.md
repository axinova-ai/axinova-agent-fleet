# VPN Client Onboarding Scripts

Automated batch provisioning scripts for WireGuard VPN clients.

## Quick Start

```bash
# Install prerequisites
brew install yq qrencode

# Run batch onboarding for all clients
./onboard-vpn-clients.sh

# Verify deployment
./verify-vpn-clients.sh

# Interactive distribution helper
./distribute-client-configs.sh /tmp/vpn-onboarding-YYYYMMDD-HHMMSS/
```

## Scripts

### onboard-vpn-clients.sh

Main orchestration script for batch client onboarding.

**What it does:**
1. Parses `ansible/inventories/vpn/clients.yml`
2. Generates key pairs on server (idempotent)
3. Fetches keys to local temp directory
4. Generates client configs and QR codes
5. Updates Ansible variables automatically
6. Deploys server configuration
7. Verifies all clients registered
8. Organizes outputs by device type

**Usage:**
```bash
./onboard-vpn-clients.sh                # Normal run (skip existing keys)
./onboard-vpn-clients.sh --force-regenerate  # Rotate all keys
```

**Output:** `/tmp/vpn-onboarding-YYYYMMDD-HHMMSS/`

**Security:** Temporary directory contains private keys - delete after distribution.

### verify-vpn-clients.sh

Automated verification of VPN server configuration and client registration.

**What it checks:**
- ✅ Server connectivity
- ✅ WireGuard service status
- ✅ All clients registered
- ✅ No duplicate IPs
- ✅ No duplicate public keys
- ✅ Server public key matches
- ✅ Connected client count

**Usage:**
```bash
./verify-vpn-clients.sh
```

**Exit codes:**
- 0: All checks passed
- 1: One or more checks failed

### distribute-client-configs.sh

Interactive helper for distributing client configurations.

**Features:**
- Menu-driven client selection
- Display QR codes in terminal
- Open QR code images
- Show device-specific distribution instructions
- Copy config paths to clipboard

**Usage:**
```bash
./distribute-client-configs.sh /tmp/vpn-onboarding-YYYYMMDD-HHMMSS/
```

**Navigation:**
- Select client by number
- View config, QR code, or instructions
- Copy paths to clipboard (macOS)
- `q` to quit

## Workflow

```
1. Edit inventory → 2. Run onboarding → 3. Verify → 4. Distribute → 5. Test
       ↓                    ↓                ↓           ↓           ↓
   clients.yml      onboard-vpn-         verify-    distribute-  Client
                    clients.sh           vpn-       client-      testing
                                        clients.sh  configs.sh
```

## Prerequisites

**Tools:**
```bash
yq          # YAML parser
qrencode    # QR code generator
ansible     # Already installed
ssh         # Access to sg-vpn
jq          # JSON processor (usually pre-installed)
```

**SSH Configuration:**
```
Host sg-vpn
    HostName 8.222.187.10
    User root
    IdentityFile ~/.ssh/axinova-sg-vpn
```

## Client Inventory

All clients are defined in: `ansible/inventories/vpn/clients.yml`

**Example:**
```yaml
clients:
  - name: device-name
    device_type: macos
    ip: 10.66.66.X
    description: "Device description"
    generate_qr: true  # Optional, for mobile
```

**To add a new client:**
1. Edit `clients.yml`
2. Run `./onboard-vpn-clients.sh`
3. Distribute new config

## Security Notes

**Safe to commit:**
- ✅ `clients.yml` (no secrets)
- ✅ Public keys
- ✅ Scripts and templates

**NEVER commit:**
- ❌ Private keys
- ❌ Generated configs (contain private keys)
- ❌ `/tmp/vpn-onboarding-*` directories

**Cleanup after distribution:**
```bash
rm -rf /tmp/vpn-onboarding-*
```

## Troubleshooting

**Keys already exist:**
```bash
# Normal - script is idempotent
# To rotate keys:
./onboard-vpn-clients.sh --force-regenerate
```

**Verification fails:**
```bash
# Check server status
ssh sg-vpn 'sudo wg show wg0'

# Review logs
ssh sg-vpn 'sudo journalctl -u wg-quick@wg0 -n 50'
```

**Client can't connect:**
```bash
# Verify client config
cat /etc/wireguard/wg0.conf

# Check interface status
sudo wg show wg0

# Test connectivity
ping 10.66.66.1
```

## Documentation

Full documentation: `../../docs/vpn/ONBOARDING.md`

- Detailed workflow
- Device-specific instructions
- Security considerations
- Advanced operations
- Architecture diagrams

## Support

For issues or questions:
1. Check `docs/vpn/ONBOARDING.md`
2. Review script output and error messages
3. Run `./verify-vpn-clients.sh` for diagnostics
