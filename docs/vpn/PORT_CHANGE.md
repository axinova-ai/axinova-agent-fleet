# VPN Port Change Guide

## Architecture: Stable Relay Port (implemented 2026-03-07)

```
Clients (AmneziaWG 2.0 apps)
    │
    │  UDP 39999 (stable port — NEVER changes in client configs)
    ▼
Aliyun Console Firewall (swas.console.aliyun.com)
    │
    ▼
UFW (on server)
    │
    ▼
iptables DNAT: 39999 → 13231 (internal AWG port, can rotate freely)
    │
    ▼
amneziawg-go (userspace, listening on internal port)
    │
    ▼
awg0 interface (10.66.66.1/24)
    │
    ▼
iptables MASQUERADE → eth0 → internet
```

### Design Decision

**Problem:** Every time GFW blocks a port, all 13 client configs across phones/laptops/desktops need manual updates — QR codes rescanned, configs reimported. This is painful and error-prone.

**Solution:** A two-layer port architecture using iptables DNAT:

1. **Stable relay port (39999):** The only port clients ever see. Hardcoded in all client configs. Open permanently in Aliyun security group and UFW. Never changes.
2. **Internal AWG port (currently 13231):** The port `amneziawg-go` actually listens on. Can be rotated freely when GFW blocks it. Only referenced in `awg0.conf` and the iptables DNAT rule.

**How it works:** iptables PREROUTING DNAT rewrites incoming UDP packets destined for port 39999 to port 13231 before they reach amneziawg-go. The kernel's conntrack automatically rewrites the source port on response packets from 13231 back to 39999, so the client sees a consistent port.

**Why it feels smoother:** When GFW starts targeting a port, it typically throttles before hard-blocking (packet loss, increased latency). A freshly rotated internal port has zero GFW attention, giving clean throughput. The stable relay port itself is less likely to be targeted since GFW sees the internal port rotation as "the service disappeared."

### Current State

| Component | Value |
|-----------|-------|
| Client-facing stable port | UDP 39999 |
| Internal AWG listen port | UDP 13231 |
| iptables DNAT rule | `udp dpt:39999 → :13231` |
| Rules persisted at | `/etc/iptables/rules.v4` |

## Port Rotation (when GFW blocks the internal port)

**One command, zero client changes:**

```bash
./scripts/rotate-vpn-port.sh <new_internal_port>
# Example: ./scripts/rotate-vpn-port.sh 27845
```

The script handles everything server-side:
1. Updates `awg0.conf` ListenPort
2. Updates iptables DNAT rule: 39999 → new port
3. Persists iptables rules to `/etc/iptables/rules.v4`
4. Restarts `awg-quick@awg0`
5. Updates UFW (opens new, closes old internal port)
6. Updates ansible references in the repo

**No client action needed.** All devices keep connecting to port 39999.

### Manual rotation (if script unavailable)

```bash
NEW_PORT=27845
OLD_PORT=13231  # check: grep ListenPort /etc/amnezia/amneziawg/awg0.conf

# 1. Update server config
ssh sg-vpn "sed -i 's/ListenPort = ${OLD_PORT}/ListenPort = ${NEW_PORT}/' /etc/amnezia/amneziawg/awg0.conf"

# 2. Update iptables DNAT
ssh sg-vpn "iptables -t nat -D PREROUTING -p udp --dport 39999 -j DNAT --to-destination :${OLD_PORT} 2>/dev/null; \
            iptables -t nat -A PREROUTING -p udp --dport 39999 -j DNAT --to-destination :${NEW_PORT}; \
            iptables-save > /etc/iptables/rules.v4"

# 3. Restart service
ssh sg-vpn "systemctl restart awg-quick@awg0"

# 4. Update UFW
ssh sg-vpn "ufw allow ${NEW_PORT}/udp; ufw delete allow ${OLD_PORT}/udp; ufw reload"

# 5. Verify
ssh sg-vpn "awg show awg0 | head -5 && iptables -t nat -L PREROUTING -n | grep 39999"
```

## Aliyun Console Firewall

Only port **39999** needs to be open permanently. Internal port changes do NOT require Aliyun console updates.

Go to https://swas.console.aliyun.com → Server → Firewall:
- Protocol: **UDP**
- Port: **39999**
- Source: `0.0.0.0/0`
- Policy: Allow

> **Important:** This is separate from UFW inside the VM. Both must allow the stable port.

## Verify After Rotation

```bash
# Check AWG is listening on new internal port
ssh sg-vpn "ss -ulnp | grep amnezia"

# Check DNAT rule points to new internal port
ssh sg-vpn "iptables -t nat -L PREROUTING -n"

# Watch traffic arriving on stable port 39999
ssh sg-vpn "timeout 15 tcpdump -i eth0 udp port 39999 -n -c 5"
# Toggle VPN on a phone while running

# Check handshake after client connects
ssh sg-vpn "awg show awg0"
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No packets on port 39999 | Aliyun console firewall missing rule | Add UDP 39999 in swas.console.aliyun.com |
| Packets on 39999 but no handshake | DNAT rule missing/wrong | Re-add: `iptables -t nat -A PREROUTING -p udp --dport 39999 -j DNAT --to-destination :<internal_port>` |
| Handshake but no internet | Missing MASQUERADE | `iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o eth0 -j MASQUERADE` |
| Worked then stopped | GFW blocked internal port | Run `./scripts/rotate-vpn-port.sh <new_port>` |
| amneziawg-go stuck (0 transfer, all peers) | Process in bad state after aggressive restart | `systemctl restart awg-quick@awg0` |
| After server reboot, DNAT gone | iptables rules not persisted | `iptables-save > /etc/iptables/rules.v4` (iptables-persistent should auto-restore) |

## Port History

| Date | Client Port | Internal Port | Protocol | Reason |
|------|-------------|---------------|----------|--------|
| 2026-02-08 | 51820 | 51820 | WireGuard | Initial setup (default WireGuard port) |
| 2026-02-09 | 443 | 443 | WireGuard | ISP blocked 51820; switched to UDP 443 |
| 2026-02-13 | 443 | 443 | AmneziaWG | Migrated to AmneziaWG for DPI evasion; kept UDP 443 |
| 2026-02-14 | 54321 | 54321 | AmneziaWG | Chinese ISPs block UDP 443 return traffic |
| 2026-03-07 | **39999** | 13231 | AmneziaWG | GFW blocked 54321; introduced stable relay port architecture |

**Bad ports:** 51820 (default WG, targeted), 443 (Chinese ISPs block UDP 443 return traffic), 54321 (GFW blocked after ~3 weeks)
