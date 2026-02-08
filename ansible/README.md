# Ansible Automation

Ansible playbooks and roles for automating infrastructure setup in the axinova-agent-fleet.

## Directory Structure

```
ansible/
├── ansible.cfg                        # Ansible configuration
├── inventories/
│   └── vpn/
│       └── hosts.ini                  # VPN server inventory
├── playbooks/
│   └── vpn_server.yml                 # VPN server setup playbook
├── roles/
│   └── wireguard_server/              # WireGuard VPN server role
│       ├── defaults/main.yml          # Default variables
│       ├── tasks/main.yml             # Installation tasks
│       ├── templates/wg0.conf.j2      # Server config template
│       └── handlers/main.yml          # Service handlers
└── scripts/
    ├── setup-vpn.sh                   # VPN server setup wrapper
    └── generate-client-qr.sh          # Generate client QR codes
```

## VPN Server Setup

### Prerequisites

- Ansible installed: `brew install ansible`
- SSH access to sg-vpn host (8.222.187.10)
- SSH config entry in `~/.ssh/config` for `sg-vpn`

### Quick Setup

```bash
cd /Users/weixia/axinova/axinova-agent-fleet/ansible
./scripts/setup-vpn.sh
```

This will:
1. Install WireGuard on the server
2. Generate server keys
3. Configure firewall (UFW)
4. Enable IP forwarding
5. Start WireGuard service

### Server Details

After setup, the server will be configured with:

- **Server Public Key:** `4utg8R6pINVXmF0EilIQx2LAtndqO0plkv2kdEwf3QE=`
- **Server Endpoint:** `8.222.187.10:51820`
- **Server VPN IP:** `10.66.66.1`
- **VPN Network:** `10.66.66.0/24`

### Verify Setup

```bash
# Check WireGuard status
ssh sg-vpn 'wg show wg0'

# View configuration
ssh sg-vpn 'cat /etc/wireguard/wg0.conf'

# Check firewall
ssh sg-vpn 'ufw status'

# View service logs
ssh sg-vpn 'journalctl -u wg-quick@wg0 -n 50'
```

## Adding Clients

### 1. Generate Client Keys

On your laptop or the client machine:

```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

### 2. Add Client to Server

Edit `ansible/roles/wireguard_server/defaults/main.yml`:

```yaml
mac_mini_1_pubkey: "<CLIENT_PUBLIC_KEY>"
```

Re-run the playbook:

```bash
./scripts/setup-vpn.sh
```

### 3. Configure Client

See: [docs/vpn/CLIENT_SETUP.md](../docs/vpn/CLIENT_SETUP.md)

## Client IP Assignments

| Client | IP Address | Variable Name |
|--------|------------|---------------|
| mac-mini-1 | 10.66.66.2 | mac_mini_1_pubkey |
| mac-mini-2 | 10.66.66.3 | mac_mini_2_pubkey |
| windows-1 | 10.66.66.4 | windows_1_pubkey |
| windows-2 | 10.66.66.5 | windows_2_pubkey |
| android | 10.66.66.6 | android_pubkey |

Additional clients can use IPs from 10.66.66.7 onwards (add them to defaults/main.yml).

## Generating QR Codes for Mobile

```bash
cd ansible/scripts
./generate-client-qr.sh android 10.66.66.6
```

This will:
1. Generate client keys
2. Create configuration file
3. Generate QR code (PNG and terminal)
4. Show instructions to add peer to server

## Updating Server Configuration

To update any server settings (network range, DNS, firewall rules), modify the variables in:
- `ansible/roles/wireguard_server/defaults/main.yml` - Default variables
- `ansible/inventories/vpn/hosts.ini` - Host-specific overrides

Then re-run:

```bash
./scripts/setup-vpn.sh
```

## Troubleshooting

### Service won't start

```bash
# Check logs
ssh sg-vpn 'journalctl -xeu wg-quick@wg0.service -n 50'

# Validate config syntax
ssh sg-vpn 'wg-quick strip wg0'
```

### Firewall blocking connections

```bash
# Verify UFW rules
ssh sg-vpn 'ufw status verbose'

# Check if port is listening
ssh sg-vpn 'ss -uln | grep 51820'
```

### Client can't connect

1. Verify server public key matches what client has
2. Check client public key is added to server config
3. Ensure firewall allows UDP 51820
4. Test from different network (some block UDP)

## Security Notes

- Private keys are generated once and stored in `/etc/wireguard/keys/` with 600 permissions
- Only SSH (22/tcp) and WireGuard (51820/udp) ports are open
- UFW deny policy for all other incoming traffic
- NAT rules only apply to VPN network (10.66.66.0/24)

## Next Steps

1. Setup clients following [docs/vpn/CLIENT_SETUP.md](../docs/vpn/CLIENT_SETUP.md)
2. Test connectivity: `ping 10.66.66.1` from client
3. Verify internet routing: `curl ifconfig.me` should show Singapore IP
4. Monitor connections: `ssh sg-vpn 'wg show wg0'`
