# Fleet Access Cheatsheet

Quick reference for connecting to Mac mini agent nodes.

## SSH (Command Line)

```bash
# Via LAN (same network)
ssh agent01-lan          # M4 Mac mini (192.168.3.6)
ssh agent02-lan          # M2 Pro Mac mini (192.168.3.5)

# Via VPN (remote, requires AmneziaWG connected)
ssh agent01              # M4 Mac mini (10.66.66.3)
ssh agent02              # M2 Pro Mac mini (10.66.66.2)
```

These aliases are configured in `~/.ssh/config`. See [SSH Config](#ssh-config) below.

## SSH Script (Auto-Detect Best Path)

```bash
cd ~/axinova/axinova-agent-fleet

./scripts/ssh-to-agent1.sh       # M4 — tries VPN first, falls back to LAN
./scripts/ssh-to-agent2.sh       # M2 Pro — tries VPN first, falls back to LAN
```

## RustDesk (Remote Desktop / GUI)

Open RustDesk on your MacBook, enter the target machine's ID:

| Machine | RustDesk ID | Use For |
|---------|-------------|---------|
| M4 Mac mini (Agent1) | `61 423 085` | GUI tasks, Docker Desktop, browser testing |
| M2 Pro Mac mini (Agent2) | *(check RustDesk app)* | Ollama UI, system settings |

RustDesk works from anywhere — no VPN needed.

## VNC / Screen Sharing (LAN or VPN only)

```bash
# Via LAN
open vnc://192.168.3.6       # M4
open vnc://192.168.3.5       # M2 Pro

# Via VPN
open vnc://10.66.66.3        # M4
open vnc://10.66.66.2        # M2 Pro
```

## Fleet Status

```bash
cd ~/axinova/axinova-agent-fleet
./scripts/fleet-status.sh
```

## Network Map

| Machine | User | LAN IP | VPN IP | RustDesk ID |
|---------|------|--------|--------|-------------|
| M4 Mac mini (Agent1) | `agent01` | `192.168.3.6` | `10.66.66.3` | `61 423 085` |
| M2 Pro Mac mini (Agent2) | `focusagent02` | `192.168.3.5` | `10.66.66.2` | *(check app)* |
| VPN Server (SG) | `root` | — | `10.66.66.1` | — |

## SSH Config

Add to `~/.ssh/config` (already configured on Wei's MacBook):

```
# M4 Mac mini (Agent1) - VPN
Host agent01
  HostName 10.66.66.3
  User agent01
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ForwardAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 3

# M4 Mac mini (Agent1) - LAN
Host agent01-lan
  HostName 192.168.3.6
  User agent01
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ForwardAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 3

# M2 Pro Mac mini (Agent2) - VPN
Host agent02
  HostName 10.66.66.2
  User focusagent02
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ForwardAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 3

# M2 Pro Mac mini (Agent2) - LAN
Host agent02-lan
  HostName 192.168.3.5
  User focusagent02
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ForwardAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

## Port Forwarding

```bash
ssh -L 9000:localhost:9000 agent01       # Portainer
ssh -L 11434:localhost:11434 agent02     # Ollama
ssh -L 5432:localhost:5432 agent01       # PostgreSQL
```

## Troubleshooting

```bash
# Can't SSH? Check connectivity:
ping 192.168.3.6          # LAN to M4
ping 10.66.66.3           # VPN to M4

# SSH key issues:
ssh-add -l                # List loaded keys
ssh -vvv agent01-lan      # Verbose SSH debug

# RustDesk not connecting:
ssh agent01-lan "pgrep -x RustDesk || open /Applications/RustDesk.app"
```
