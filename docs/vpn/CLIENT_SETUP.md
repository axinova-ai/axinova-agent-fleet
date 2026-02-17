# AmneziaWG VPN Client Setup Guide

This guide covers setting up AmneziaWG VPN clients to connect to the Singapore VPN server (8.222.187.10).

> **Migration Note (2026-02-13):** The VPN has been migrated from WireGuard to AmneziaWG. AmneziaWG is a fork of WireGuard that adds traffic obfuscation to bypass Deep Packet Inspection (DPI) used by Chinese ISPs. The underlying WireGuard protocol and cryptography remain unchanged.

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

Note: Keys are still stored at `/etc/wireguard/keys/` even though AmneziaWG configs are at `/etc/amnezia/amneziawg/`.

## Server Details

- **Server Endpoint:** `8.222.187.10:54321`
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

### Installation

1. **Install AmneziaWG:**
   ```bash
   # Download from GitHub releases
   # https://github.com/amnezia-vpn/amneziawg-apple/releases
   # Install the .pkg file for macOS
   ```

   Or use Homebrew if available:
   ```bash
   brew install amneziawg-tools
   ```

2. **Generate keys:**
   ```bash
   awg genkey | tee privatekey | awg pubkey > publickey
   ```

3. **Create config** at `/etc/amnezia/amneziawg/awg0.conf`:
   ```ini
   [Interface]
   PrivateKey = <content of privatekey file>
   Address = 10.66.66.2/24  # Use assigned IP
   DNS = 1.1.1.1
   Jc = 3
   Jmin = 50
   Jmax = 1000
   S1 = 0
   S2 = 0
   H1 = 1
   H2 = 2
   H3 = 3
   H4 = 4

   [Peer]
   PublicKey = <SERVER_PUBLIC_KEY>
   Endpoint = 8.222.187.10:54321
   AllowedIPs = 0.0.0.0/0
   PersistentKeepalive = 25
   ```

4. **Secure the config:**
   ```bash
   sudo mkdir -p /etc/amnezia/amneziawg
   sudo chmod 600 /etc/amnezia/amneziawg/awg0.conf
   ```

### Starting the VPN

**Manual start:**
```bash
sudo awg-quick up awg0
```

**Stop:**
```bash
sudo awg-quick down awg0
```

**Auto-start on boot:**
```bash
# Create launchd plist (similar to WireGuard but for AmneziaWG)
sudo systemctl enable awg-quick@awg0  # On Linux
# For macOS, create a custom launchd plist pointing to awg-quick
```

---

## Windows Setup

### Installation

1. Download AmneziaWG for Windows from: https://github.com/amnezia-vpn/amneziawg-windows/releases
2. Run the installer (requires admin privileges)

### Configuration

1. **Generate keys** (in PowerShell):
   ```powershell
   # Install AmneziaWG first, then use its CLI
   cd "C:\Program Files\AmneziaWG"
   .\awg.exe genkey | Tee-Object -FilePath privatekey | .\awg.exe pubkey > publickey
   ```

2. **Create config file** `awg0-sg.conf`:
   ```ini
   [Interface]
   PrivateKey = <content of privatekey>
   Address = 10.66.66.4/24  # windows-1, use 10.66.66.5 for windows-2
   DNS = 1.1.1.1
   Jc = 3
   Jmin = 50
   Jmax = 1000
   S1 = 0
   S2 = 0
   H1 = 1
   H2 = 2
   H3 = 3
   H4 = 4

   [Peer]
   PublicKey = <SERVER_PUBLIC_KEY>
   Endpoint = 8.222.187.10:54321
   AllowedIPs = 0.0.0.0/0
   PersistentKeepalive = 25
   ```

3. **Import in AmneziaWG GUI:**
   - Open AmneziaWG application
   - Click "Import tunnel(s) from file"
   - Select the `awg0-sg.conf` file
   - Click "Activate"

### Managing Connection

- **Connect:** Click "Activate" in AmneziaWG GUI
- **Disconnect:** Click "Deactivate"
- **Auto-start:** Right-click tunnel → "Enable at boot"

---

## Android Setup

### Installation

1. Install AmneziaWG from Google Play Store: Search for "AmneziaWG"

### Configuration via QR Code (Recommended)

1. **Generate QR code on your laptop:**
   ```bash
   cd /Users/weixia/axinova/axinova-agent-fleet/ansible/scripts
   ./generate-client-qr.sh android 10.66.66.6
   ```

2. **Scan QR code:**
   - Open AmneziaWG app on Android
   - Tap "+" button
   - Select "Scan from QR code"
   - Scan the QR code displayed in terminal or saved PNG
   - The obfuscation parameters are automatically included

3. **Name the tunnel** (e.g., "SG VPN")

### Manual Configuration

1. **Generate keys on laptop** (easier than on mobile):
   ```bash
   awg genkey | tee android_private.key | awg pubkey > android_public.key
   ```

2. **In AmneziaWG app:**
   - Tap "+" → "Create from scratch"
   - **Interface section:**
     - Name: `SG VPN`
     - Private key: Paste from `android_private.key`
     - Addresses: `10.66.66.6/24`
     - DNS servers: `1.1.1.1`
     - **AmneziaWG settings:**
       - Jc: `3`
       - Jmin: `50`
       - Jmax: `1000`
       - S1: `0`, S2: `0`
       - H1: `1`, H2: `2`, H3: `3`, H4: `4`

   - **Peer section:**
     - Public key: `<SERVER_PUBLIC_KEY>`
     - Endpoint: `8.222.187.10:54321`
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

1. Install AmneziaWG from App Store: https://apps.apple.com/us/app/amneziawg/id6478942365
2. Use QR code method (recommended) or manual config
3. When scanning QR code, the obfuscation parameters are automatically included
4. Manual config requires entering the same AmneziaWG settings as Android (Jc, Jmin, Jmax, S1, S2, H1-H4)
5. Assigned IP: Use available IP from range (e.g., 10.66.66.7)

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
   sudo nano /etc/amnezia/amneziawg/awg0.conf
   ```

3. **Add peer section:**
   ```ini
   [Peer] # mac-mini-1
   PublicKey = <CLIENT_PUBLIC_KEY>
   AllowedIPs = 10.66.66.2/32
   ```

4. **Restart AmneziaWG:**
   ```bash
   sudo awg-quick down awg0
   sudo awg-quick up awg0
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

3. **Check AmneziaWG status:**
   ```bash
   # macOS/Linux
   sudo awg show

   # Windows (PowerShell as admin)
   & "C:\Program Files\AmneziaWG\awg.exe" show
   ```
   Expected: Shows interface, peer, latest handshake

### On Server

```bash
ssh sg-vpn 'awg show awg0'
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
   ssh sg-vpn 'systemctl status awg-quick@awg0'
   ```

2. **Verify firewall allows UDP 54321:**
   ```bash
   ssh sg-vpn 'sudo ufw status'
   ```

3. **Check client public key is on server:**
   ```bash
   ssh sg-vpn 'sudo cat /etc/amnezia/amneziawg/awg0.conf | grep -A 2 "YOUR_PUBLIC_KEY"'
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
   ssh sg-vpn 'sudo journalctl -u awg-quick@awg0 -n 50'
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
   - Restart AmneziaWG: `sudo awg-quick down awg0 && sudo awg-quick up awg0`

4. **Monitor connections:**
   - Regularly check active peers: `ssh sg-vpn 'awg show'`
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

- AmneziaWG GitHub: https://github.com/amnezia-vpn/amneziawg
- AmneziaWG iOS App: https://github.com/amnezia-vpn/amneziawg-apple
- AmneziaWG Windows App: https://github.com/amnezia-vpn/amneziawg-windows
- WireGuard Official Site (original protocol): https://www.wireguard.com/

---

## Support

For issues with VPN setup:
1. Check this guide's troubleshooting section
2. Review server logs: `ssh sg-vpn 'journalctl -u awg-quick@awg0'`
3. Verify configuration files match examples (including obfuscation parameters)
4. Test connectivity step-by-step (ping, curl, handshake)
5. Ensure obfuscation parameters (Jc, Jmin, Jmax, S1, S2, H1-H4) match server config
