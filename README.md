# Axinova Agent Fleet

Multi-agent team infrastructure running on two Mac minis for autonomous software development, operations, and documentation.

## Architecture

```
You (PM) ──► Discord ──► OpenClaw (M4, Kimi K2.5) ──► Vikunja Task
                                                            │
                              ┌─────────────────────────────┘
                              ▼
        ┌─ M4 Mac Mini (agent01, 16GB) ───────────────────────┐
        │  Agent Launcher (polling Vikunja via API)             │
        │  ├── Backend SDE  (Codex CLI on *-go repos)          │
        │  ├── Frontend SDE (Codex CLI on *-web repos)         │
        │  OpenClaw (Kimi K2.5 → task routing)                 │
        │  AmneziaWG VPN (10.66.66.3)                          │
        └──────────────────────────────────────────────────────┘
                              │ Thunderbolt Bridge (10.10.10.x)
        ┌─ M2 Pro Mac Mini (focusagent02, 16GB) ──────────────┐
        │  Agent Launcher (polling Vikunja via API)             │
        │  ├── DevOps/QA   (Codex CLI)                         │
        │  ├── Tech Writer (Codex CLI)                         │
        │  Ollama LLM Server (Qwen 2.5 7B, Gemma 3 4B)        │
        │  AmneziaWG VPN (10.66.66.2)                          │
        └──────────────────────────────────────────────────────┘

LLM Strategy (native CLIs, no abstraction layers):
  Routing:  Kimi K2.5 (Moonshot) → OpenClaw native on M4
  Coding:   Codex CLI (OpenAI)   → primary autonomous agent on both machines
  Simple:   Qwen/Gemma (Ollama)  → routine tasks on M2 Pro (future)
  Review:   Claude Code (human)  → PR review + merge on MacBook Air

Both machines → GitHub (harryxiaxia) → PRs to axinova-ai org repos
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

1. You send a task via Discord → OpenClaw (Kimi K2.5) → Vikunja task
2. Agent launcher polls Vikunja API every 2 min, picks up tasks matching its role label
3. Agent runs Codex CLI (`codex --approval-mode full-auto`) with role-specific instructions
4. Agent implements, tests, commits, pushes branch, creates PR via `gh`
5. Updates Vikunja task as done, notifies Discord
6. You review PR with Claude Code on MacBook, approve, merge

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

### 3. Configure Codex CLI + GitHub

```bash
# Codex CLI auth (OpenAI login)
codex  # First run prompts for OpenAI auth

# GitHub auth
gh auth login --with-token <<< "<PAT>"

# Git identity (set during bootstrap):
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
agent-instructions/     # Role-specific prompts for Codex CLI
bootstrap/
  mac/                  # Mac mini setup (Homebrew, tools)
  vpn/                  # AmneziaWG VPN setup
  github/               # GitHub auth setup (SSH keys + PAT)
scripts/
  agent-launcher.sh     # Core: polls Vikunja API, runs Codex CLI
  fleet-status.sh       # Check fleet health
launchd/                # macOS LaunchAgent plists for persistence
openclaw/               # OpenClaw + Discord setup (Kimi K2.5)
integrations/mcp/       # MCP server config
runners/                # Local CI (Go, Vue, Docker) + deployment
docs/                   # Agent teams, runbooks, architecture
```

## Security

- **VPN:** AmneziaWG (DPI-resistant) to Singapore server (8.222.187.10:54321)
- **Auth:** Fine-grained GitHub PAT, stored in 1Password
- **Secrets:** SOPS + age encryption
- **Isolation:** Dedicated agent users (`agent01`, `focusagent02`)
- **Network:** Thunderbolt bridge between minis (10.10.10.0/24), Tailscale mesh

## Documentation

- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Detailed setup guide
- [PROGRESS.md](PROGRESS.md) - Progress tracking
- [docs/AGENT_TEAMS.md](docs/AGENT_TEAMS.md) - Agent roles and coordination
- [docs/runbooks/](docs/runbooks/) - Operational runbooks
- [docs/vpn/](docs/vpn/) - VPN setup guides
