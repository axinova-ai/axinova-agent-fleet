# VPN Troubleshooting Runbook

Operational reference for diagnosing and fixing AmneziaWG VPN issues.

## Architecture Overview

```
Clients (AmneziaWG 2.0 apps)
    │
    │  UDP 54321 (obfuscated)
    ▼
Aliyun Console Firewall (swas.console.aliyun.com)
    │
    ▼
UFW (on server)
    │
    ▼
amneziawg-go (userspace, NOT kernel module)
    │
    ▼
awg0 interface (10.66.66.1/24)
    │
    ▼
iptables MASQUERADE → eth0 → internet
```

- **Server:** 8.222.187.10:54321 (private: 172.19.24.184)
- **Subnet:** 10.66.66.0/24
- **Config:** `/etc/amnezia/amneziawg/awg0.conf`
- **Service:** `awg-quick@awg0`
- **Process:** `amneziawg-go awg0` (userspace)

## Quick Health Check

```bash
# One-liner status
ssh sg-vpn 'sudo /usr/local/bin/check-vpn-health.sh'

# Detailed peer status
ssh sg-vpn 'sudo awg show awg0'

# Verify userspace process is running
ssh sg-vpn 'ps aux | grep amneziawg-go | grep -v grep'

# Check service status
ssh sg-vpn 'systemctl status awg-quick@awg0'
```

## Symptom → Diagnosis → Fix

### 1. Client says "unable to establish connection" / handshake timeout

**Diagnosis steps:**

```bash
# Step 1: Is the server running?
ssh sg-vpn 'sudo awg show awg0 | head -5'
# If "Unable to access interface" → service is down, go to Fix A

# Step 2: Are packets reaching the server?
ssh sg-vpn 'sudo timeout 15 tcpdump -i eth0 udp port 54321 -n -c 10'
# Toggle VPN on phone/laptop while tcpdump runs
# If NO packets → port blocked, go to Fix B
# If packets arrive → continue to step 3

# Step 3: Does server respond?
# In tcpdump output, look for BOTH directions:
#   client_ip.port > 172.19.24.184.54321  (inbound)
#   172.19.24.184.54321 > client_ip.port  (outbound response)
# If server responds but no handshake → ISP blocking return traffic, go to Fix C
# If server does NOT respond → protocol issue, go to Fix D

# Step 4: Check peer status
ssh sg-vpn 'sudo awg show awg0'
# Look for the client's peer:
#   "transfer: X received, Y sent" but NO "latest handshake" → obfuscation or version mismatch, go to Fix D
#   "latest handshake: X seconds ago" → VPN is working, client-side issue
```

**Fix A: Service is down**
```bash
ssh sg-vpn 'sudo systemctl restart awg-quick@awg0'
# Verify
ssh sg-vpn 'sudo awg show awg0 | head -3'
```

**Fix B: Port blocked (no packets reaching server)**
```bash
# Check UFW
ssh sg-vpn 'sudo ufw status | grep 54321'
# If missing:
ssh sg-vpn 'sudo ufw allow 54321/udp'

# Check Aliyun console firewall
# Go to swas.console.aliyun.com → Server → Firewall
# Ensure UDP 54321 is listed. Server reboots may reset this.
```

**Fix C: ISP blocking return traffic on current port → change port**
```bash
# Pick a new random port (e.g., 38291)
NEW_PORT=38291

# Server side
ssh sg-vpn "sudo awg-quick down awg0 && sudo sed -i 's/ListenPort = 54321/ListenPort = $NEW_PORT/' /etc/amnezia/amneziawg/awg0.conf && sudo ufw allow $NEW_PORT/udp && sudo awg-quick up awg0"

# Verify
ssh sg-vpn "sudo awg show awg0 | grep 'listening port'"

# Open port in Aliyun console firewall (swas.console.aliyun.com)

# Update client configs locally
cd ~/axinova/axinova-agent-fleet
find vpn-distribution/configs -name "*.conf" -exec sed -i '' "s/8.222.187.10:54321/8.222.187.10:$NEW_PORT/g" {} \;

# Regenerate QR codes for mobile devices
for f in vpn-distribution/configs/ios/wei-iphone.conf vpn-distribution/configs/ios/lisha-iphone.conf vpn-distribution/configs/android/wei-android-xiaomi-ultra14.conf; do
    dir=$(dirname "$f")
    name=$(basename "$f" .conf)
    qrencode -o "$dir/$name.png" < "$f"
    qrencode -t ansiutf8 < "$f" > "$dir/$name.txt"
done

# Update repo references
sed -i '' "s/54321/$NEW_PORT/g" ansible/inventories/vpn/clients.yml
sed -i '' "s/54321/$NEW_PORT/g" ansible/roles/wireguard_server/defaults/main.yml
sed -i '' "s/54321/$NEW_PORT/g" ansible/scripts/generate-client-qr.sh
sed -i '' "s/54321/$NEW_PORT/g" bootstrap/vpn/wg0.conf.template

# Redistribute: phones scan new QR, desktops update Endpoint port
```

**Fix D: Protocol / obfuscation mismatch**
```bash
# Check packet sizes in tcpdump to verify obfuscation is working:
ssh sg-vpn 'sudo timeout 15 tcpdump -i eth0 udp port 54321 -n'
# Client should send: 5 junk packets (varying sizes) + 193-byte init (148 + S1=45)
# Server should respond: 167-byte packet (92 + S2=75)
# If client sends exactly 148 bytes → client NOT applying obfuscation (wrong app or missing params)

# Verify no kernel module conflict
ssh sg-vpn 'lsmod | grep -E "amneziawg|wireguard"'
# Should return NOTHING (userspace mode). If a module is loaded:
ssh sg-vpn 'sudo rmmod amneziawg 2>/dev/null; sudo rmmod wireguard 2>/dev/null; sudo systemctl restart awg-quick@awg0'

# Verify obfuscation params in server config match client config
ssh sg-vpn 'grep -E "Jc|Jmin|Jmax|S1|S2|H1|H2|H3|H4" /etc/amnezia/amneziawg/awg0.conf'
# Must match exactly: Jc=5, Jmin=50, Jmax=1000, S1=45, S2=75, H1=1009484, H2=2147444, H3=3088611, H4=4166003
```

### 2. VPN connects but no internet access

```bash
# Check NAT/MASQUERADE
ssh sg-vpn 'sudo iptables -t nat -L POSTROUTING -v | grep MASQUERADE'
# Should show: MASQUERADE  all  --  10.66.66.0/24  anywhere

# If missing (e.g., after restart):
ssh sg-vpn 'sudo iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE'

# Check FORWARD rules
ssh sg-vpn 'sudo ufw status | grep awg0'
# Should show:
#   Anywhere on eth0  ALLOW FWD  Anywhere on awg0
#   Anywhere on awg0  ALLOW FWD  Anywhere on eth0

# Check IP forwarding
ssh sg-vpn 'sysctl net.ipv4.ip_forward'
# Should be: net.ipv4.ip_forward = 1
```

### 3. VPN worked then stopped after hours/days

**Most likely cause:** ISP started blocking the port.

```bash
# Quick test: can packets still reach server?
ssh sg-vpn 'sudo timeout 10 tcpdump -i eth0 udp port 54321 -n -c 3'
# Toggle VPN on client while running

# If packets arrive and server responds but no handshake → ISP blocking return, change port (Fix C above)
# If no packets arrive at all → Aliyun firewall reset (check console) or ISP blocking inbound too
```

**Other causes:**
- Server rebooted and Aliyun console firewall reset → re-add UDP port rule
- `amneziawg-go` process crashed → `sudo systemctl restart awg-quick@awg0`
- Unattended-upgrades broke something → check `journalctl -u awg-quick@awg0 -n 50`

### 4. Server rebooted

```bash
# Check service came back up
ssh sg-vpn 'systemctl status awg-quick@awg0'
ssh sg-vpn 'ps aux | grep amneziawg-go | grep -v grep'

# Verify kernel module NOT loaded (should use userspace)
ssh sg-vpn 'lsmod | grep amneziawg'
# Should be empty. Blacklist at /etc/modprobe.d/blacklist-amneziawg.conf

# Re-check Aliyun console firewall — it may reset on reboot
# swas.console.aliyun.com → Firewall → verify UDP 54321 exists
```

## If DPI Catches Up (Escalation Options)

If changing ports no longer works (ISP fingerprinting the protocol itself):

| Option | Difficulty | Description |
|--------|-----------|-------------|
| **Change obfuscation params** | Easy | Generate new random Jc/Jmin/Jmax/S1/S2/H1-H4, update all configs |
| **Add AmneziaWG 2.0 params** | Medium | Add S3, S4, I1-I5 for deeper concealment (requires 2.0 server+client) |
| **Wrap in Cloak/shadowsocks** | Hard | Tunnel UDP inside TLS-looking traffic |
| **Switch to VLESS/Reality** | Hard | Completely different protocol that mimics real HTTPS to a real website |

### Changing Obfuscation Params

```bash
# Generate new random values (example)
# Jc: 1-10, Jmin: 10-100, Jmax: 500-1500, S1: 10-100, S2: 10-100
# H1-H4: random large integers (must match on all clients)

# Update server
ssh sg-vpn 'sudo vi /etc/amnezia/amneziawg/awg0.conf'
ssh sg-vpn 'sudo systemctl restart awg-quick@awg0'

# Update ALL client configs with the same new values
# Update ansible/roles/wireguard_server/defaults/main.yml
# Update ansible/scripts/onboard-vpn-clients.sh (if hardcoded)
# Regenerate QR codes for mobile devices
```

## Key File Locations

| What | Path |
|------|------|
| Server config | `/etc/amnezia/amneziawg/awg0.conf` |
| Kernel module blacklist | `/etc/modprobe.d/blacklist-amneziawg.conf` |
| amneziawg-go binary | `/usr/local/bin/amneziawg-go` |
| Health check script | `/usr/local/bin/check-vpn-health.sh` |
| Server keys | `/etc/wireguard/keys/` |
| Client keys | `/etc/wireguard/clients/` |
| Client configs (local) | `vpn-distribution/configs/{ios,android,macos,windows}/` |
| Ansible role | `ansible/roles/wireguard_server/` |
| Inventory | `ansible/inventories/vpn/clients.yml` |

## Port Change History

| Date | Port | Protocol | Reason |
|------|------|----------|--------|
| 2026-02-08 | 51820 | WireGuard | Initial setup |
| 2026-02-09 | 443 | WireGuard | ISP blocked 51820 |
| 2026-02-13 | 443 | AmneziaWG | Migrated for DPI evasion |
| 2026-02-14 | 54321 | AmneziaWG | ISP blocks UDP 443 return traffic |
