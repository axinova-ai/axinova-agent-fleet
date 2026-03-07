# Axinova Agent Fleet

Generic builder agent pool running on Mac minis for autonomous software development, operations, and documentation.

## Architecture

```
Founder (Wei, MacBook Air + Claude Code)
    │  High-level intent ("ship feature X", "fix bug Y")
    ▼
Orchestrator (OpenClaw on M4, Kimi K2.5)
    │  Decomposes into atomic tasks, labels, sequences
    │  Creates Vikunja tasks with rich descriptions
    ▼
Vikunja Kanban (Project 13: Agent Fleet)
    │  Tasks labeled by category: backend, frontend, devops, etc.
    │  Builders claim any unclaimed task (generic pool)
    ▼
Builder Pool (10 agents on M4, polling every 120s)
    │  Detect repo from task title → cd into it
    │  Codex CLI → Kimi K2.5 → Ollama (fallback chain)
    │  Implement → Test → Commit → Push → PR
    ▼
Founder reviews PR → merge

Alternative entry: Discord → OpenClaw → Vikunja → Builder
Alternative entry: Claude Code → MCP vikunja_create_task → Builder
```

### Machines

```
┌─ M4 Mac Mini (agent01, 16GB) ───────────────────────┐
│  10× Builder Agents (generic, any task)              │
│  OpenClaw (Discord → Vikunja orchestrator)           │
│  Local Console Bot (Discord → Ollama direct chat)    │
│  Ollama tunnel (→ M2 Pro via Thunderbolt)            │
│  AmneziaWG VPN (10.66.66.3)                          │
└──────────────────────────────────────────────────────┘
                │ Thunderbolt Bridge (10.10.10.x)
┌─ M2 Pro Mac Mini (focusagent02, 16GB) ──────────────┐
│  Ollama LLM Server (Qwen 2.5 Coder 7B)              │
│  AmneziaWG VPN (10.66.66.2)                          │
└──────────────────────────────────────────────────────┘

LLM Model Chain (all builders, fallback order):
  1. Codex CLI (ChatGPT auth)  → primary coding, built-in file tools
  2. Kimi K2.5 (Moonshot API)  → cloud fallback, unified diff protocol
  3. Ollama qwen2.5-coder:7b   → local fallback, zero cloud cost
```

## Key Concepts

### Builders are generic
Every agent is identical — same code, same tools, same access to all repos. No specialization by role (backend, frontend, etc.). A builder picks up any unclaimed task and figures out what to do from the task description.

### Labels are categories, not routing
Labels describe the type of work for reporting and filtering. They don't control which agent picks up a task. A task can have up to 5 labels.

| Label | Use for |
|-------|---------|
| `backend` | Go APIs, handlers, sqlc, migrations |
| `frontend` | Vue 3, TypeScript, PrimeVue, Tailwind |
| `devops` | Docker, Traefik, CI/CD, deployment, deps |
| `infra` | Database setup, tooling, provisioning |
| `qa` | E2E testing, release sign-off |
| `testing` | Unit tests, integration tests, coverage |
| `tech-writer` | Wiki, runbooks, API docs |
| `docs` | READMEs, architecture docs |
| `urgent` | Priority flag |
| `blocked` | Needs unblocking |

### Orchestrator decomposes work
The orchestrator's job is breaking high-level goals into atomic tasks (one PR each) that maximize parallelism. Task title must include the repo name so builders know where to work.

### Repo detection
Builders detect which repo to work in by scanning the task title for `axinova-*` patterns. If no repo is found, the task escalates to the founder. All repos live under `~/workspace/`.

## How It Works

### Flow 1: Claude Code → Vikunja → Builder (Design-first)

1. Design features locally with Claude Code on MacBook Air
2. Create tasks in Vikunja via MCP (`vikunja_create_task`) with labels and descriptions
3. Builder agent polls Vikunja, claims unclaimed task
4. Builder detects repo, implements, tests, pushes branch, creates PR
5. Review PR with Claude Code, approve, merge

### Flow 2: Discord → OpenClaw → Vikunja → Builder (Quick dispatch)

1. Send message in Discord → OpenClaw decomposes into Vikunja tasks
2. Builder claims task → implements → PR
3. Review and merge

### Audit Trail

Every task has structured comments:
```
[2026-03-07 14:30] [CLAIMED] Agent builder-3 on M4 picking up task
[2026-03-07 14:31] [STARTED] Model: codex-cli | Repo: axinova-home-go | Agent: builder-3
[2026-03-07 14:35] [IN REVIEW] PR: https://github.com/... | Duration: 4m
```

## Quick Start

### 1. Bootstrap Mac Mini

```bash
ssh agent01@<mac-mini-ip>
cd ~/workspace/axinova-agent-fleet/bootstrap/mac
./setup-macos.sh
```

### 2. Configure Secrets

```bash
mkdir -p ~/.config/axinova && chmod 700 ~/.config/axinova

# Vikunja token
echo 'export APP_VIKUNJA__TOKEN=tk_...' > ~/.config/axinova/vikunja.env
chmod 600 ~/.config/axinova/vikunja.env

# Moonshot API key (for Kimi K2.5)
echo 'MOONSHOT_API_KEY=sk-...' > ~/.config/axinova/moonshot.env
chmod 600 ~/.config/axinova/moonshot.env
```

### 3. Start Agents

```bash
# Manual (for testing)
./scripts/agent-launcher.sh builder-1 ~/workspace 120

# Persistent (launchd)
cp launchd/com.axinova.agent-builder-*.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-builder-*.plist
```

### 4. Check Status

```bash
./scripts/fleet-status.sh
```

## Repository Structure

```
agent-instructions/
  builder.md            # Universal builder instructions (all agents use this)
  backend-sde.md        # Legacy (kept for reference)
  frontend-sde.md       # Legacy (kept for reference)
  devops.md             # Legacy (kept for reference)
  qa-testing.md         # Legacy (kept for reference)
  tech-writer.md        # Legacy (kept for reference)
scripts/
  agent-launcher.sh     # Core: polls Vikunja, multi-model execution, audit trail
  fleet-status.sh       # Fleet health dashboard
  benchmark-ollama.sh   # Local LLM benchmark
launchd/
  com.axinova.agent-builder-{1..10}.plist  # 10 identical builder agents
  com.axinova.openclaw.plist               # Orchestrator daemon
  com.axinova.local-console-bot.plist      # Discord → Ollama chat
  com.axinova.vikunja-tunnel.plist         # SSH tunnel to Vikunja
  com.axinova.ollama-tunnel.plist          # SSH tunnel M4→M2 Pro
openclaw/
  task-router-prompt.md # Orchestrator prompt (decompose, label, sequence)
  openclaw.json         # Multi-agent + multi-provider config
  setup.sh              # Install & configure OpenClaw
  discord-setup.sh      # Create Discord channels & webhooks
docs/                   # Runbooks, architecture
```

## Security

- **VPN:** AmneziaWG (DPI-resistant) to Singapore server (8.222.187.10:39999)
- **Auth:** Fine-grained GitHub PAT, stored in 1Password
- **Secrets:** `~/.config/axinova/*.env` (chmod 600) — NOT in plist files
- **Isolation:** Dedicated agent user (`agent01`)
- **Network:** Thunderbolt bridge between minis, SSH tunnels for services
