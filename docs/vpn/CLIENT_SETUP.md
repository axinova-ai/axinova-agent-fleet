# WireGuard VPN Client Setup Guide

This guide covers setting up WireGuard VPN clients to connect to the Singapore VPN server (8.222.187.10).

## Prerequisites

Before configuring clients, ensure the VPN server is set up:

```bash
cd /Users/weixia/axinova/axinova-agent-fleet/ansible
./scripts/setup-vpn.sh
```

Get the server public key:

```bash
ssh sg-vpn 'cat /etc/wireguard/keys/server_public.key'
```

You'll need this key for all client configurations below.

## Server Details

- **Server Endpoint:** `8.222.187.10:51820`
- **Server VPN IP:** `10.66.66.1`
- **VPN Network:** `10.66.66.0/24`
- **DNS:** `1.1.1.1`

## Client IP Assignments

| Client | IP Address |
|--------|------------|
| mac-mini-1 | 10.66.66.2 |
| mac-mini-2 | 10.66.66.3 |
| windows-1 | 10.66.66.4 |
| windows-2 | 10.66.66.5 |
| android | 10.66.66.6 |

---

## macOS / Mac mini Setup

### Option 1: Using Bootstrap Script (Recommended)

```bash
cd /Users/weixia/axinova/axinova-agent-fleet/bootstrap/vpn
./wireguard-install.sh
```

This script will:
1. Install WireGuard via Homebrew
2. Generate client keys
3. Create config template at `/etc/wireguard/wg0.conf`

### Option 2: Manual Setup

1. **Install WireGuard:**
   ```bash
   brew install wireguard-tools
   ```

2. **Generate keys:**
   ```bash
   wg genkey | tee privatekey | wg pubkey > publickey
   ```

3. **Create config** at `/etc/wireguard/wg0.conf`:
   ```ini
   [Interface]
   PrivateKey = <content of privatekey file>
   Address = 10.66.66.2/24  # Use assigned IP
   DNS = 1.1.1.1

   [Peer]
   PublicKey = <SERVER_PUBLIC_KEY>
   Endpoint = 8.222.187.10:51820
   AllowedIPs = 0.0.0.0/0
   PersistentKeepalive = 25
   ```

4. **Secure the config:**
   ```bash
   sudo chmod 600 /etc/wireguard/wg0.conf
   ```

### Starting the VPN

**Manual start:**
```bash
sudo wg-quick up wg0
```

**Stop:**
```bash
sudo wg-quick down wg0
```

**Auto-start on boot:**
```bash
# Create launchd plist
sudo cp /Users/weixia/axinova/axinova-agent-fleet/bootstrap/vpn/com.wireguard.wg0.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.wireguard.wg0.plist
```

**Using connect script:**
```bash
cd /Users/weixia/axinova/axinova-agent-fleet/bootstrap/vpn
./connect-sg.sh
```

---

## Windows Setup

### Installation

1. Download WireGuard for Windows from: https://www.wireguard.com/install/
2. Run the installer (requires admin privileges)

### Configuration

1. **Generate keys** (in PowerShell):
   ```powershell
   # Install WireGuard first, then use its CLI
   cd "C:\Program Files\WireGuard"
   .\wg.exe genkey | Tee-Object -FilePath privatekey | .\wg.exe pubkey > publickey
   ```

2. **Create config file** `wg0-sg.conf`:
   ```ini
   [Interface]
   PrivateKey = <content of privatekey>
   Address = 10.66.66.4/24  # windows-1, use 10.66.66.5 for windows-2
   DNS = 1.1.1.1

   [Peer]
   PublicKey = <SERVER_PUBLIC_KEY>
   Endpoint = 8.222.187.10:51820
   AllowedIPs = 0.0.0.0/0
   PersistentKeepalive = 25
   ```

3. **Import in WireGuard GUI:**
   - Open WireGuard application
   - Click "Import tunnel(s) from file"
   - Select the `wg0-sg.conf` file
   - Click "Activate"

### Managing Connection

- **Connect:** Click "Activate" in WireGuard GUI
- **Disconnect:** Click "Deactivate"
- **Auto-start:** Right-click tunnel → "Enable at boot"

---

## Android Setup

### Installation

1. Install WireGuard from Google Play Store: https://play.google.com/store/apps/details?id=com.wireguard.android

### Configuration via QR Code (Easiest)

1. **Generate QR code on your laptop:**
   ```bash
   cd /Users/weixia/axinova/axinova-agent-fleet/ansible/scripts
   ./generate-client-qr.sh android 10.66.66.6
   ```

2. **Scan QR code:**
   - Open WireGuard app on Android
   - Tap "+" button
   - Select "Scan from QR code"
   - Scan the QR code displayed in terminal or saved PNG

3. **Name the tunnel** (e.g., "SG VPN")

### Manual Configuration

1. **Generate keys on laptop** (easier than on mobile):
   ```bash
   wg genkey | tee android_private.key | wg pubkey > android_public.key
   ```

2. **In WireGuard app:**
   - Tap "+" → "Create from scratch"
   - **Interface section:**
     - Name: `SG VPN`
     - Private key: Paste from `android_private.key`
     - Addresses: `10.66.66.6/24`
     - DNS servers: `1.1.1.1`

   - **Peer section:**
     - Public key: `<SERVER_PUBLIC_KEY>`
     - Endpoint: `8.222.187.10:51820`
     - Allowed IPs: `0.0.0.0/0`
     - Persistent keepalive: `25`

3. **Save** the configuration

### Connecting

- Tap the toggle switch next to "SG VPN"
- First connection will ask for VPN permission - grant it
- Connected status shows encryption stats

---

## iOS Setup (iPhone/iPad)

Similar to Android:

1. Install WireGuard from App Store: https://apps.apple.com/us/app/wireguard/id1441195209
2. Use QR code method or manual config (same steps as Android)
3. Assigned IP: Use available IP from range (e.g., 10.66.66.7)

---

## Adding Client to Server

After generating client keys, you **must** add the client's public key to the server:

### Option 1: Via Ansible (Recommended)

1. **Edit** `ansible/roles/wireguard_server/defaults/main.yml`:
   ```yaml
   mac_mini_1_pubkey: "<CLIENT_PUBLIC_KEY>"
   ```

2. **Re-run playbook:**
   ```bash
   cd /Users/weixia/axinova/axinova-agent-fleet/ansible
   ./scripts/setup-vpn.sh
   ```

### Option 2: Manual Server Configuration

1. **SSH to server:**
   ```bash
   ssh sg-vpn
   ```

2. **Edit config:**
   ```bash
   sudo nano /etc/wireguard/wg0.conf
   ```

3. **Add peer section:**
   ```ini
   [Peer] # mac-mini-1
   PublicKey = <CLIENT_PUBLIC_KEY>
   AllowedIPs = 10.66.66.2/32
   ```

4. **Restart WireGuard:**
   ```bash
   sudo wg-quick down wg0
   sudo wg-quick up wg0
   ```

---

## Verification

### On Client

1. **Ping the VPN server:**
   ```bash
   ping 10.66.66.1
   ```
   Expected: Replies from 10.66.66.1

2. **Check public IP:**
   ```bash
   curl ifconfig.me
   ```
   Expected: `8.222.187.10` (Singapore IP)

3. **Check WireGuard status:**
   ```bash
   # macOS/Linux
   sudo wg show

   # Windows (PowerShell as admin)
   & "C:\Program Files\WireGuard\wg.exe" show
   ```
   Expected: Shows interface, peer, latest handshake

### On Server

```bash
ssh sg-vpn 'wg show wg0'
```

Expected output:
- Lists connected peers
- Shows latest handshake (should be recent, < 2 minutes)
- Transfer counters (RX/TX bytes)

---

## Troubleshooting

### Cannot Connect

1. **Check server is running:**
   ```bash
   ssh sg-vpn 'systemctl status wg-quick@wg0'
   ```

2. **Verify firewall allows UDP 51820:**
   ```bash
   ssh sg-vpn 'sudo ufw status'
   ```

3. **Check client public key is on server:**
   ```bash
   ssh sg-vpn 'sudo cat /etc/wireguard/wg0.conf | grep -A 2 "YOUR_PUBLIC_KEY"'
   ```

### No Internet Access

1. **Check AllowedIPs** in client config is `0.0.0.0/0` (full tunnel)
2. **Verify IP forwarding** on server:
   ```bash
   ssh sg-vpn 'sysctl net.ipv4.ip_forward'
   ```
   Should return: `net.ipv4.ip_forward = 1`

3. **Check NAT rules:**
   ```bash
   ssh sg-vpn 'sudo iptables -t nat -L POSTROUTING -n -v'
   ```

### Handshake Never Completes

1. **Time sync issue** - ensure client and server clocks are synchronized
2. **Wrong server public key** - verify you're using the correct key
3. **Network blocking UDP** - some networks block UDP; try from different network

### Connection Drops

1. **Add PersistentKeepalive:**
   Ensure client config has: `PersistentKeepalive = 25`

2. **Check server logs:**
   ```bash
   ssh sg-vpn 'sudo journalctl -u wg-quick@wg0 -n 50'
   ```

---

## Security Best Practices

1. **Protect private keys:**
   - Never share or commit private keys
   - Use 600 permissions: `chmod 600 privatekey`

2. **Rotate keys regularly:**
   - Recommended: Every 6-12 months
   - Generate new keys and update both client and server

3. **Revoke compromised keys:**
   - Remove peer from server config
   - Restart WireGuard: `sudo wg-quick down wg0 && sudo wg-quick up wg0`

4. **Monitor connections:**
   - Regularly check active peers: `ssh sg-vpn 'wg show'`
   - Watch for unknown public keys

---

## Split Tunneling (Optional)

To route only specific traffic through VPN (not all internet):

**Change AllowedIPs** in client config:
```ini
# Only route VPN network through tunnel
AllowedIPs = 10.66.66.0/24

# Or specific services
AllowedIPs = 10.66.66.0/24, 192.168.1.0/24
```

This keeps normal internet traffic on local connection, only VPN network goes through tunnel.

---

## Additional Resources

- WireGuard Official Site: https://www.wireguard.com/
- WireGuard Quick Start: https://www.wireguard.com/quickstart/
- Troubleshooting Guide: https://www.wireguard.com/quickstart/#nat-and-firewall-traversal-persistence

---

## Support

For issues with VPN setup:
1. Check this guide's troubleshooting section
2. Review server logs: `ssh sg-vpn 'journalctl -u wg-quick@wg0'`
3. Verify configuration files match examples
4. Test connectivity step-by-step (ping, curl, handshake)
