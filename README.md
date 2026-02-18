# Axinova Agent Fleet

Multi-agent team infrastructure running on two Mac minis for autonomous software development, operations, and documentation.

## Architecture

```
You (PM) ──► Discord ──► OpenClaw (M4) ──► Vikunja Task
                                                │
                         ┌──────────────────────┘
                         ▼
        ┌─ M4 Mac Mini (24GB) ─────────────────────────┐
        │  Agent Launcher (polling Vikunja)              │
        │  ├── Backend SDE  (claude -p on *-go repos)   │
        │  ├── Frontend SDE (claude -p on *-web repos)  │
        │  MCP Server → Vikunja, SilverBullet, etc.     │
        │  AmneziaWG VPN (10.66.66.3)                   │
        └───────────────────────────────────────────────┘
                         │ Thunderbolt Bridge
        ┌─ M2 Pro Mac Mini (32GB) ─────────────────────┐
        │  Agent Launcher (polling Vikunja)              │
        │  ├── DevOps/QA   (deploys, tests, monitoring) │
        │  ├── Tech Writer (docs, runbooks)             │
        │  MCP Server → same tools                      │
        │  AmneziaWG VPN (10.66.66.2)                   │
        └───────────────────────────────────────────────┘

Both machines → GitHub (harryxiaxia + per-machine identity) → PRs to axinova-ai org repos
Both machines → MCP → Vikunja, SilverBullet, Portainer, Grafana, Prometheus
```

## Agent Roles

### M4 Mac Mini - Production Team (24GB RAM)
- **Backend SDE** - Go APIs, database, tests (chi v5, sqlc, PostgreSQL)
- **Frontend SDE** - Vue 3, TypeScript, PrimeVue, Tailwind

### M2 Pro Mac Mini - Ops & Quality Team (32GB RAM)
- **DevOps** - Docker Compose deployment, monitoring, Traefik
- **QA & Testing** - Test suites, security scanning, coverage
- **Technical Writer** - Wiki updates, API docs, runbooks

## How It Works

1. You send a task via Discord → OpenClaw → Vikunja
2. Agent launcher polls Vikunja every 2 min, picks up tasks matching its role label
3. Agent runs `claude -p` with role-specific instructions in the target repo
4. Agent implements, tests, commits, pushes, creates PR
5. Updates Vikunja task, logs to SilverBullet wiki
6. You review PR on GitHub, approve, merge

## Quick Start

### 1. Bootstrap Mac Mini

```bash
ssh weixia@<mac-mini-ip>
cd ~/workspace/axinova-agent-fleet/bootstrap/mac
./setup-macos.sh
```

### 2. Configure VPN

```bash
cd ~/workspace/axinova-agent-fleet/bootstrap/vpn
./amneziawg-setup.sh
```

### 3. Configure Claude Code + GitHub

```bash
sudo -i -u axinova-agent
export ANTHROPIC_API_KEY=<key>
claude auth login
gh auth login --with-token <<< "<PAT>"
# Git identity is set automatically by setup-macos.sh:
#   M4:     "Axinova M4 Agent" <m4@axinova.local>
#   M2 Pro: "Axinova M2Pro Agent" <m2pro@axinova.local>
```

### 4. Start Agents

```bash
# Manual start (for testing)
./scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go

# Or install launchd daemons (persistent)
cp launchd/com.axinova.agent-*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-*.plist
```

## Repository Structure

```
agent-instructions/     # Role-specific Claude system prompts
bootstrap/
  mac/                  # Mac mini setup (Homebrew, users, tools)
  vpn/                  # AmneziaWG VPN setup
  github/               # GitHub auth setup (SSH keys + PAT)
scripts/
  agent-launcher.sh     # Core: polls Vikunja, runs claude -p
  fleet-status.sh       # Check fleet health
launchd/                # macOS LaunchAgent plists for persistence
openclaw/               # OpenClaw + Discord setup
integrations/mcp/       # MCP server config for Claude Code
runners/                # Local CI (Go, Vue, Docker) + deployment
docs/                   # Agent teams, runbooks, architecture
```

## Security

- **VPN:** AmneziaWG (DPI-resistant) to Singapore server (8.222.187.10:54321)
- **Auth:** Fine-grained GitHub PAT, stored in 1Password
- **Secrets:** SOPS + age encryption
- **Isolation:** Dedicated `axinova-agent` user with restricted sudo
- **Network:** Thunderbolt bridge between minis (169.254.100.0/24)

## Documentation

- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Detailed setup guide
- [PROGRESS.md](PROGRESS.md) - Progress tracking
- [docs/AGENT_TEAMS.md](docs/AGENT_TEAMS.md) - Agent roles and coordination
- [docs/runbooks/](docs/runbooks/) - Operational runbooks
- [docs/vpn/](docs/vpn/) - VPN setup guides
