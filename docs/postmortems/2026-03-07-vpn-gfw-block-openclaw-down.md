# Post-Mortem: VPN Port Blocked by GFW + OpenClaw Discord Bot Down

**Date:** 2026-03-07
**Duration:** ~4 hours (from detection to full resolution)
**Impact:** All VPN clients disconnected; OpenClaw Discord bot offline; agent-launchers on M4 unable to receive new tasks via Discord
**Severity:** High — complete agent fleet communication blackout

---

## Timeline

| Time (CST) | Event |
|------------|-------|
| ~22:00 Mar 6 | User notices OpenClaw Discord bot not responding |
| 22:15 | SSH to M4 reveals Discord DNS failures (`getaddrinfo ENOTFOUND gateway-us-east1-*.discord.gg`) — GFW blocking |
| 22:30 | While debugging, discover VPN is down for ALL clients (M4, M2 Pro, iPhone, Xiaomi) |
| 22:45 | SSH to VPN server (sg-vpn) — server healthy, awg0 running, but `awg show` shows 0 transfers for all peers |
| 23:00 | Confirmed: GFW blocked UDP 54321 (simultaneous drop across all China ISPs) |
| 23:15 | Changed server AWG port to 13231, updated all client configs |
| 23:30 | Aliyun security group updated for UDP 13231 |
| 23:45 | tcpdump shows iPhone packets arriving but server NOT responding — amneziawg-go stuck |
| 00:12 | `systemctl restart awg-quick@awg0` — fresh process resolves stuck state |
| 00:22 | iPhone handshake completes on port 13231. VPN restored. |
| 00:30 | Implemented stable relay port: iptables DNAT 39999 → 13231 |
| 00:45 | All client configs updated to port 39999 (permanent). QR codes regenerated. |
| 01:00 | Phones rescanned QR codes — brief failure because old config (54321) was cached in AmneziaWG app |
| 01:10 | After deleting old tunnels and reimporting, all phones connected via 39999 |
| 02:00 | Mac Mini VPN configs updated (M4 + M2 Pro) |
| 04:30 | M4 code pulled, M4 SSH key added to VPN server authorized_keys |
| 04:46 | OpenClaw restarted with SOCKS5 proxy — Discord bot online |

---

## Root Causes

### 1. GFW blocked UDP port 54321

**What happened:** China's Great Firewall detected sustained encrypted UDP traffic on port 54321 to our Singapore server (8.222.187.10) and blocked it. All clients in China dropped simultaneously.

**Why it wasn't caught earlier:** AmneziaWG obfuscation prevents DPI-based detection of the WireGuard protocol itself, but GFW can still do traffic pattern analysis — consistent high-bandwidth encrypted UDP to a single IP:port is suspicious regardless of payload obfuscation.

**Contributing factor:** Port 54321 had been in use for 3 weeks (since Feb 14). Longer usage = higher probability of detection.

### 2. amneziawg-go stuck after aggressive restart

**What happened:** During debugging, the awg0 interface was deleted while `amneziawg-go` was still running (`pkill + ip link delete`). SSH dropped mid-operation, leaving the process in a zombie state — socket bound to port 13231, accepting no packets, producing zero responses.

**Signs:** `awg show awg0 transfer` showed 0 for ALL peers. tcpdump showed inbound packets but zero outbound. Process appeared healthy (`ss -unlp` showed socket bound).

**Fix:** `systemctl restart awg-quick@awg0` — clean restart with new PID.

### 3. OpenClaw Discord bot blocked by GFW

**What happened:** Discord WebSocket gateway (`gateway-us-east1-*.discord.gg`) is blocked by GFW. With full-tunnel VPN (AllowedIPs = 0.0.0.0/0), Discord traffic was routed through the VPN to Singapore and worked. When VPN dropped, Discord became unreachable.

**Why it didn't auto-recover when VPN came back:** OpenClaw didn't have a proxy mechanism. It relied entirely on the VPN for Discord access. Additionally, the `openclaw-start.sh` script had been updated with SOCKS5 proxy support, but the code wasn't pulled to M4 yet (VPN was down when we committed).

### 4. SOCKS5 tunnel auth failure

**What happened:** Even after pulling the proxy code, the SOCKS5 tunnel (`ssh -D 1080 root@8.222.187.10`) failed because M4's SSH key wasn't in the VPN server's `authorized_keys`.

### 5. Stale phone configs (old port cached)

**What happened:** After scanning new QR codes (port 39999), the AmneziaWG app on both phones still had the old tunnel (port 54321) active. The app tried the old config first. dmesg on the server confirmed: `[UFW BLOCK] ... DPT=54321` from the phones' IP.

---

## What Went Well

1. **VPN server itself was stable** — 25 days uptime, no crash, no reboot needed
2. **Diagnosis was systematic** — tcpdump + awg show + strace narrowed down each issue
3. **proxy-bootstrap.cjs worked first try** — self-contained SOCKS5 interceptor with no npm dependencies
4. **Stable relay port architecture** was designed and implemented during the incident, preventing future pain

---

## Lessons Learned

### 1. Never expose the real AWG port to clients

**Before:** Client configs pointed directly to the AWG listen port. Every port change required updating 13+ device configs, redistributing QR codes, and physically accessing desktops.

**After:** Clients use a stable relay port (39999) via iptables DNAT. Port rotation is a single server-side command: `./scripts/rotate-vpn-port.sh <new_port>`.

### 2. Don't delete network interfaces while SSH'd through them

Running `ip link delete awg0` while the amneziawg-go process is running causes a stuck state. The process holds the socket but can't process packets without the tun device. Always use `systemctl restart awg-quick@awg0` for clean restarts.

### 3. Discord access needs a proxy, not just VPN

Full-tunnel VPN is fragile — if VPN drops, Discord goes down. The SOCKS5 proxy provides defense-in-depth: even if VPN routing changes, OpenClaw can still reach Discord through the SSH tunnel.

### 4. Pre-authorize SSH keys for all automation paths

M4's agent key must be in the VPN server's `authorized_keys` for the SOCKS5 tunnel to work. This was missing and only discovered when OpenClaw tried to start the tunnel.

### 5. Delete old tunnels before importing new configs on phones

AmneziaWG apps can hold multiple tunnel configs. If the old tunnel is still active, the app may try it first — causing confusing "VPN not working" reports even though the new config is correct.

### 6. GFW port blocking is inevitable — design for rotation

With AmneziaWG obfuscation, the protocol isn't fingerprinted by DPI. But traffic analysis (sustained encrypted UDP to a fixed IP:port) will eventually trigger blocking. Plan for port rotation every 2-4 weeks, or when throughput degrades.

---

## Action Items

| # | Action | Status | Owner |
|---|--------|--------|-------|
| 1 | Implement stable relay port (iptables DNAT 39999→internal) | Done | — |
| 2 | Rewrite `rotate-vpn-port.sh` for server-side-only rotation | Done | — |
| 3 | Add M4 SSH key to VPN server authorized_keys | Done | — |
| 4 | Deploy `proxy-bootstrap.cjs` + updated `openclaw-start.sh` to M4 | Done | — |
| 5 | Update all VPN docs (PORT_CHANGE, TROUBLESHOOTING, CLIENT_SETUP) | Done | — |
| 6 | Persist iptables rules via `iptables-persistent` | Done | — |
| 7 | Consider port rotation if VPN drops become frequent | On hold | Wei |

---

## Current Fleet Architecture (as of 2026-03-07)

### M4 Mac Mini (agent01) — Command + Backend/Frontend SDEs

| Service | Count | Details |
|---------|-------|---------|
| OpenClaw Discord bot | 1 | Discord → Vikunja task routing (via SOCKS5 proxy) |
| Backend SDE agents | 6 | home-go, ai-lab-go, miniapp-builder-go, trading-agent-go, ai-social-publisher-go, mcp-server-go |
| Frontend SDE agents | 4 | home-web, trading-agent-web, miniapp-builder-web, ai-social-publisher-web |
| Codex | 1 | Code execution engine |
| Local console bot | 1 | Local model interface |

### M2 Pro Mac Mini (focusagent02) — Ops + QA + Wiki

| Service | Count | Details |
|---------|-------|---------|
| DevOps agent | 1 | axinova-deploy |
| QA Testing agent | 1 | axinova-home-go |
| Tech Writer agent | 1 | SilverBullet wiki pages |
| Codex | 1 | Code execution engine |
| Ollama | 1 | Local LLM inference |

### VPN Server (sg-vpn, 8.222.187.10) — Singapore

| Component | Details |
|-----------|---------|
| AmneziaWG | amneziawg-go v0.2.16 userspace, 15 peers |
| Stable relay port | UDP 39999 (iptables DNAT → internal 13231) |
| SOCKS5 relay | SSH tunnel endpoint for GFW bypass |

### M1 Workstation (planned) — Personal Remote Dev

| Component | Details |
|-----------|---------|
| Claude Code | Remote tunnel via `claude code tunnel` |
| Access | Phone (iPhone/Android) → Claude Code during work hours |
| VPN IP | 10.66.66.4 (ready, config generated) |
| Use case | Plan tasks, review PRs, assign work to M4/M2 agents |

---

## Workflow: Phone → Claude Code → Agent Fleet

```
Wei's Phone (during work hours 10-6)
    │
    │  Claude Code mobile app / SSH
    ▼
M1 Workstation (10.66.66.4)
    │
    │  Claude Code session
    ▼
Create Vikunja task / Discord message / direct git operations
    │
    ├──→ OpenClaw (M4) ──→ Routes to appropriate agent
    │
    ├──→ M4 agent-launchers (10 SDEs) ──→ Backend + Frontend PRs
    │
    └──→ M2 agent-launchers (3 ops) ──→ DevOps + QA + Wiki
```

The M1 workstation acts as Wei's remote hands — a full dev environment accessible from phone, capable of orchestrating the entire agent fleet while Wei is at the day job.
