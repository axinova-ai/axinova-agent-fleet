# VPN Port Change Guide

## Why Change Ports

Chinese ISPs use Deep Packet Inspection (DPI) to fingerprint and block VPN traffic. They can detect WireGuard's default port (51820) and even the WireGuard protocol itself. UDP 443 was initially used (looks like QUIC/HTTPS) but Chinese ISPs started blocking UDP 443 return traffic. Port 54321 is now used as a less commonly targeted high port.

**Migration to AmneziaWG:** As of 2026-02-13, the VPN has been migrated from WireGuard to AmneziaWG. AmneziaWG adds traffic obfuscation to bypass DPI, making it much harder for ISPs to detect and block VPN traffic even if they inspect packets.

**Current port:** UDP 54321
**Bad ports:** 51820 (default WG), 443 (Chinese ISPs block UDP 443 return traffic)

## Port Change Checklist

### 1. Server Config

```bash
ssh sg-vpn "sed -i 's/^ListenPort = OLD_PORT/ListenPort = NEW_PORT/' /etc/amnezia/amneziawg/awg0.conf"
ssh sg-vpn "awg-quick down awg0 && awg-quick up awg0"
```

### 2. Aliyun Console Firewall

Go to https://swas.console.aliyun.com → Server → Firewall → Add rule:
- Protocol: **UDP**
- Port: **NEW_PORT**
- Source: `0.0.0.0/0`
- Policy: Allow

> **Important:** This is separate from UFW inside the VM. Both must allow the port.

### 3. Client Configs (all 10 .conf files)

```bash
cd axinova-agent-fleet
# Update all client configs
find vpn-distribution/configs -name "*.conf" -exec sed -i '' 's/8.222.187.10:OLD_PORT/8.222.187.10:NEW_PORT/g' {} \;
```

### 4. QR Codes (3 mobile devices)

```bash
qrencode -t PNG -o vpn-distribution/qr-codes/wei-iphone.png < vpn-distribution/configs/ios/wei-iphone.conf
qrencode -t UTF8 -o vpn-distribution/qr-codes/wei-iphone.txt < vpn-distribution/configs/ios/wei-iphone.conf

qrencode -t PNG -o vpn-distribution/qr-codes/wei-android-xiaomi-ultra14.png < vpn-distribution/configs/android/wei-android-xiaomi-ultra14.conf
qrencode -t UTF8 -o vpn-distribution/qr-codes/wei-android-xiaomi-ultra14.txt < vpn-distribution/configs/android/wei-android-xiaomi-ultra14.conf

qrencode -t PNG -o vpn-distribution/qr-codes/lisha-iphone.png < vpn-distribution/configs/ios/lisha-iphone.conf
qrencode -t UTF8 -o vpn-distribution/qr-codes/lisha-iphone.txt < vpn-distribution/configs/ios/lisha-iphone.conf
```

### 5. Ansible/Repo References

Update these files:
- `ansible/inventories/vpn/clients.yml` → `server.endpoint`
- `ansible/roles/wireguard_server/defaults/main.yml` → `vpn_port`
- `ansible/inventories/vpn/hosts.ini` → `vpn_port`
- `ansible/scripts/generate-client-qr.sh` → `SERVER_ENDPOINT`
- `bootstrap/vpn/wg0.conf.template` → `Endpoint`
- `bootstrap/vpn/wireguard-install.sh` → `Endpoint`

### 6. Redistribute to Devices

- **Phones:** Delete old tunnel in AmneziaWG app, scan new QR code
- **macOS:** Replace config at `/etc/amnezia/amneziawg/awg0.conf` or edit Endpoint port
- **Windows:** Import new config in AmneziaWG GUI or edit Endpoint port

### 7. Verify

```bash
# Check server is listening on new port
ssh sg-vpn "ss -ulnp | grep NEW_PORT"

# Check UDP reaches server (from local)
ssh sg-vpn "timeout 10 tcpdump -i eth0 udp port NEW_PORT -c 3 -n &"
echo "test" | nc -u -w1 8.222.187.10 NEW_PORT

# Check handshake after client connects
ssh sg-vpn "awg show awg0"
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No packets reach server | Aliyun console firewall missing rule | Add UDP rule in swas.console.aliyun.com |
| Handshake but no internet | Missing FORWARD/NAT rules | Check `iptables -L FORWARD` and MASQUERADE |
| Worked then stopped | ISP blocked the port | Change to a different port |
| Broke after server reboot | Unattended-upgrades updated libsodium/libc6 | Reboot again; consider disabling unattended-upgrades |

## History

| Date | Port | Protocol | Reason |
|------|------|----------|--------|
| 2026-02-08 | 51820 | WireGuard | Initial setup (default WireGuard port) |
| 2026-02-09 | 443 | WireGuard | ISP blocked 51820; switched to UDP 443 |
| 2026-02-13 | 443 | AmneziaWG | Migrated to AmneziaWG for DPI evasion; kept UDP 443 |
| 2026-02-14 | 54321 | AmneziaWG | Chinese ISPs block UDP 443 return traffic; switched to 54321 |
