# Axinova Agent Fleet

Multi-agent team infrastructure running on two Mac minis for autonomous software development, operations, and documentation.

## Architecture

```
Flow 1 (Design-first):
You (MacBook Air, Claude Code) ──► MCP vikunja_create_task ──► Vikunja Task
                                                                     │
Flow 2 (Quick dispatch):                                             │
You (PM) ──► Discord ──► OpenClaw (M4, Kimi K2.5) ──► Vikunja Task  │
                                                            │        │
                              ┌─────────────────────────────┴────────┘
                              ▼
        ┌─ M4 Mac Mini (agent01, 16GB) ───────────────────────┐
        │  Agent Launcher (polling Vikunja via API)             │
        │  ├── Backend SDE  (Codex CLI / Kimi K2.5 / Ollama)  │
        │  ├── Frontend SDE (Codex CLI / Kimi K2.5 / Ollama)  │
        │  OpenClaw (Kimi K2.5 → task routing + delegation)    │
        │  Local Console Bot (Discord → Ollama direct chat)    │
        │  Ollama tunnel (→ M2 Pro via Thunderbolt)            │
        │  AmneziaWG VPN (10.66.66.3)                          │
        └──────────────────────────────────────────────────────┘
                              │ Thunderbolt Bridge (10.10.10.x)
        ┌─ M2 Pro Mac Mini (focusagent02, 16GB) ──────────────┐
        │  Agent Launcher (polling Vikunja via API)             │
        │  ├── DevOps       (Codex CLI / Kimi K2.5 / Ollama)  │
        │  ├── QA & Testing (Codex CLI / Kimi K2.5 / Ollama)  │
        │  ├── Tech Writer  (Ollama / Kimi K2.5)              │
        │  Ollama LLM Server (Qwen 2.5 Coder 7B)              │
        │  AmneziaWG VPN (10.66.66.2)                          │
        └──────────────────────────────────────────────────────┘

LLM Model Chain (fallback order):
  1. Codex CLI (ChatGPT auth)  → primary coding, built-in file tools
  2. Kimi K2.5 (Moonshot API)  → cloud fallback, unified diff protocol
  3. Ollama qwen2.5-coder:7b   → local fallback, zero cloud cost
  Simple tasks (docs/lint/format) → Ollama directly (skip cloud)

Routing:  Kimi K2.5 via OpenClaw → Discord ↔ Vikunja
Local:    Local Console Bot → Discord ↔ Ollama (direct LLM chat)
Review:   Claude Code (human)    → PR review + merge on MacBook Air

Both machines → GitHub (harryxiaxia) → PRs to axinova-ai org repos
Both machines → MCP → Vikunja, SilverBullet, Portainer, Grafana, Prometheus
```

## Agent Roles

### M4 Mac Mini - Production Team
- **Backend SDE** - Go APIs, database, tests (chi v5, sqlc, PostgreSQL)
- **Frontend SDE** - Vue 3, TypeScript, PrimeVue, Tailwind

### M2 Pro Mac Mini - Ops & Quality Team
- **DevOps** - Docker Compose deployment, monitoring, Traefik
- **QA & Testing** - Test suites, security scanning, coverage
- **Technical Writer** - Wiki updates, API docs, runbooks

## How It Works

### Flow 1: Claude Code → Vikunja → Agent (Design-first)

You design features locally with Claude Code on your MacBook Air, then delegate implementation to the fleet:

1. You use **Claude Code** to explore code, design architecture, and plan implementation
2. Claude Code creates tasks in **Vikunja via MCP** (vikunja_create_task) with appropriate labels and descriptions
3. Agent launcher polls Vikunja API every 2 min, picks up tasks matching its role label
4. Agent claims task, implements, tests, pushes branch, creates PR
5. You review PR with Claude Code on MacBook, approve, merge

```
You (MacBook Air, Claude Code)
    │  Design feature, plan implementation
    │  Create Vikunja tasks via MCP tools
    ▼
Vikunja task created (label=backend-sde, detailed description + acceptance criteria)
    │
    ▼  (polled every 120s)
Agent Launcher (Mac Mini) → Codex CLI / Kimi / Ollama
    │  Implement → Test → Push → PR
    ▼
You (MacBook Air, Claude Code) review PR → merge
```

### Flow 2: Discord → OpenClaw → Vikunja → Agent (Quick dispatch)

For quick tasks, send a message in Discord and let the task router handle labeling:

1. You send a task via Discord → OpenClaw (Kimi K2.5) → Vikunja task with auto-label
2. Agent launcher polls Vikunja API every 2 min, picks up tasks matching its role label
3. Agent claims task → **adds Vikunja comment** `[CLAIMED]`
4. Agent selects model (Codex CLI → Kimi K2.5 → Ollama) based on task type
5. Agent implements changes, tests, commits, pushes branch, creates PR via `gh`
6. Agent **comments** `[COMPLETED] PR: <url> | Model: kimi-k2.5 | Duration: 4m`
7. Agent notifies Discord with **rich embed** (model, duration, PR link)
8. You review PR with Claude Code on MacBook, approve, merge

### Audit Trail

Every task has structured comments in Vikunja:
```
[2026-03-02 14:30] [CLAIMED] Agent backend-sde on M4 picking up task
[2026-03-02 14:31] [STARTED] Model: kimi-k2.5 | Repo: axinova-home-go
[2026-03-02 14:35] [COMPLETED] PR: https://github.com/... | Model: kimi-k2.5 | Duration: 4m | Commits: 2
```

## Prerequisites

- **macOS** 26.x on Apple Silicon (M2 Pro / M4)
- **Go** 1.24+ and **Node.js** 22+
- **Docker** (for local dev stacks)
- **Ollama** (M2 Pro — local LLM inference)
- **AmneziaWG** VPN client (for remote access)
- **Homebrew** (package manager)
- **gh** CLI (GitHub operations)
- **Codex CLI** (OpenAI autonomous coding agent)

## Quick Start

### 1. Bootstrap Mac Mini

```bash
ssh weixia@<mac-mini-ip>
cd ~/workspace/axinova-agent-fleet/bootstrap/mac
./setup-macos.sh
```

### 2. Configure Secrets

```bash
# On each Mac Mini:
mkdir -p ~/.config/axinova && chmod 700 ~/.config/axinova

# Moonshot API key (for Kimi K2.5)
echo 'MOONSHOT_API_KEY=sk-...' > ~/.config/axinova/moonshot.env
chmod 600 ~/.config/axinova/moonshot.env

# Discord webhooks (generated by openclaw/discord-setup.sh)
# → ~/.config/axinova/discord-webhooks.env
```

### 3. Configure Codex CLI + GitHub

```bash
# Codex CLI auth (OpenAI login)
codex  # First run prompts for OpenAI auth

# GitHub auth
gh auth login --with-token <<< "<PAT>"
```

### 4. Start Agents

```bash
# Manual start (for testing)
./scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go

# Or install launchd daemons (persistent)
cp launchd/com.axinova.agent-*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-*.plist

# M4 only: Ollama tunnel to M2 Pro
cp launchd/com.axinova.ollama-tunnel.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.ollama-tunnel.plist
```

### 5. Check Status

```bash
./scripts/fleet-status.sh
```

## Repository Structure

```
agent-instructions/     # Role-specific prompts for LLM agents
bootstrap/
  mac/                  # Mac mini setup (Homebrew, tools)
  vpn/                  # AmneziaWG VPN setup
  github/               # GitHub auth setup (SSH keys + PAT)
scripts/
  agent-launcher.sh     # Core: polls Vikunja, multi-model execution, audit trail
  fleet-status.sh       # Fleet health dashboard + agent ledger
  benchmark-ollama.sh   # Local LLM benchmark (model comparison)
launchd/                # macOS LaunchAgent plists for persistence
  com.axinova.agent-*.plist      # 5 agent daemons
  com.axinova.openclaw.plist     # OpenClaw task router daemon
  com.axinova.local-console-bot.plist  # Local Console Bot daemon
  com.axinova.vikunja-tunnel.plist  # SSH tunnel to Vikunja (GFW bypass)
  com.axinova.ollama-tunnel.plist   # SSH tunnel M4→M2 Pro for Ollama
openclaw/               # OpenClaw + Discord setup (multi-agent, Kimi K2.5)
  openclaw.json         # Multi-agent + multi-provider config
  task-router-prompt.md # Task routing with /status, /assign, /models
  setup.sh              # Install & configure OpenClaw
  discord-setup.sh      # Create Discord channels & webhooks
integrations/
  discord-local-console/  # Local Console Bot (Discord → Ollama)
  mcp/                    # MCP server config
runners/                # Local CI (Go, Vue, Docker) + deployment
docs/                   # Agent teams, runbooks, architecture
```

## Security

- **VPN:** AmneziaWG (DPI-resistant) to Singapore server (8.222.187.10:39999, stable relay port)
- **Auth:** Fine-grained GitHub PAT, stored in 1Password
- **Secrets:** `~/.config/axinova/*.env` (chmod 600) — **NOT** in plist files
- **Isolation:** Dedicated agent users (`agent01`, `focusagent02`)
- **Network:** Thunderbolt bridge between minis (10.10.10.0/24), SSH tunnels for services

## Documentation

- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Detailed setup guide
- [PROGRESS.md](PROGRESS.md) - Progress tracking
- [docs/AGENT_TEAMS.md](docs/AGENT_TEAMS.md) - Agent roles and coordination
- [docs/runbooks/](docs/runbooks/) - Operational runbooks
- [docs/vpn/](docs/vpn/) - VPN setup guides
