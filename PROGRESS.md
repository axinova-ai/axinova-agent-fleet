# Agent Fleet Implementation Progress

Last Updated: 2026-03-02 (Phase 2 — Multi-model + Audit Trail)

## Overview

**Goal:** Two Mac minis running 5 specialized AI agents that autonomously handle software development, coordinated through Vikunja tasks and Discord.

**LLM Strategy (multi-model with fallback chain):**

| Priority | Provider | Method | Use Case |
|----------|----------|--------|----------|
| 1 | OpenAI Codex | `codex exec --full-auto` (ChatGPT auth) | Primary coding agent (built-in file tools) |
| 2 | Kimi K2.5 (Moonshot) | REST API → unified diff | Cloud fallback for coding tasks |
| 3 | Qwen 2.5 7B (Ollama) | Local inference → unified diff | Simple tasks (docs, lint, format) — zero cost |
| Routing | Kimi K2.5 (Moonshot) | OpenClaw native | Task routing from Discord → Vikunja |
| Review | Claude (Anthropic) | `claude` CLI (human) | PR review + merge (human-in-the-loop) |

**Machine Architecture:**

| Machine | Role | Tools | Network |
|---------|------|-------|---------|
| MacBook Air (192.168.3.44) | Human dev | Claude Code (Pro Max) | Wi-Fi + Tailscale |
| M4 Mac Mini (192.168.3.6, `agent01`) | Agent runner + OpenClaw | Codex CLI, Kimi K2.5, Ollama (via tunnel) | Wi-Fi + Thunderbolt (10.10.10.2) |
| M2 Pro Mac Mini (192.168.3.5, `focusagent02`) | LLM server + agents | Codex CLI, Kimi K2.5, Ollama (native) | Wi-Fi + Thunderbolt (10.10.10.1) |

**Current Status:** Phase 5 in progress. Local Console Bot (Discord → Ollama) implemented and connecting to Discord. Awaiting Message Content Intent enablement for command testing. E2E pipeline verified in Phase 3. OpenClaw gateway running on M4.

---

## Phase 0: Pre-flight Preparation

- [x] Create GitHub fine-grained PAT (`axinova-gitops-agent`)
  - [x] Scopes: contents:write, pull_requests:write, issues:write, metadata:read
  - [x] Org-scoped PAT with access to all `axinova-ai/*` repos
- [x] MCP tokens configured (Portainer, Grafana, SilverBullet, Vikunja) → deployed to both machines
- [x] Create Discord bot via Developer Portal → save token
- [x] Set up Discord channels (#agent-tasks, #agent-prs, #agent-alerts, #agent-logs)
- [x] Set up Discord webhooks for agent notifications
- [x] Set up Vikunja project "Agent Fleet" (id:13) with labels (backend-sde, frontend-sde, devops, qa, docs, urgent, blocked)

---

## Phase 1: Mac Mini Bootstrap

### M4 Mac Mini (agent01@192.168.3.6)
- [x] SSH key auth from MacBook Air
- [x] Recon: macOS 26.2, arm64, 16GB RAM, 1.8TB disk
- [x] Install Homebrew (USTC mirror for GFW)
- [x] Install tools: go, node, git, gh, jq, yq, tmux, mosh, age, sops, python@3.12, pipenv
- [x] Install Go tools: govulncheck, sqlc, migrate (via goproxy.cn)
- [x] Install Claude Code CLI v2.1.49
- [x] Install Codex CLI v0.106.0
- [x] Git identity: `"Axinova M4 Agent" <m4@axinova.local>`
- [x] SSH key: `ssh-ed25519 ...MvX0 axinova-m4-agent`
- [x] GitHub auth: `gh auth login` as `harryxiaxia`
- [x] Clone all 14 axinova-ai repos (org PAT)
- [x] MCP config deployed to `~/.claude/settings.json` with real tokens
- [x] MCP server built: `~/workspace/axinova-mcp-server-go/bin/axinova-mcp-server`
- [x] AmneziaVPN installed + connected
- [x] Codex CLI authenticated (OpenAI login)
- [ ] Tailscale logged in (deferred — SSH tunnel approach preferred)

### M2 Pro Mac Mini (focusagent02@192.168.3.5)
- [x] SSH key auth from MacBook Air
- [x] Recon: macOS 26.3, arm64, 16GB RAM, 460GB disk
- [x] Install Homebrew (USTC mirror for GFW)
- [x] Install tools: go, node, git, gh, jq, yq, tmux, mosh, age, sops, python@3.12, pipenv
- [x] Install Go tools: govulncheck, sqlc, migrate (via goproxy.cn)
- [x] Install Claude Code CLI v2.1.49
- [x] Install Codex CLI v0.106.0
- [x] Git identity: `"Axinova M2Pro Agent" <m2pro@axinova.local>`
- [x] SSH key: `ssh-ed25519 ...2vb axinova-m2pro-agent`
- [x] GitHub auth: `gh auth login` as `harryxiaxia` (org PAT)
- [x] Install Ollama + pull Qwen 2.5 7B + Qwen 2.5 Coder 7B
- [x] Ollama listening on 0.0.0.0:11434
- [x] Clone all 14 axinova-ai repos (org PAT)
- [x] MCP config deployed to `~/.claude/settings.json` with real tokens
- [x] MCP server built: `~/workspace/axinova-mcp-server-go/bin/axinova-mcp-server`
- [x] AmneziaVPN installed + connected
- [x] Codex CLI authenticated (OpenAI login)
- [ ] Tailscale logged in (deferred)
- [ ] Pull Gemma 3 4B (blocked by VPN IPv6 routing, defer)

### Verification Checklist
- [x] `claude --version` works on both machines → v2.1.49
- [x] `codex --version` works on both machines → v0.106.0
- [x] `codex` auth (OpenAI login) on both machines
- [x] `go version` → 1.24+, `node --version` → 22+
- [x] `gh auth status` → logged in as `harryxiaxia` on both

---

## Phase 2: Thunderbolt Bridge + VPN + Tunnels

- [x] Thunderbolt Bridge: M4=10.10.10.2, M2 Pro=10.10.10.1 (sub-ms latency)
- [x] Ollama on M2 Pro listening on 0.0.0.0:11434 (PlistBuddy fix + custom plist backup)
- [x] M4 can reach Ollama via Thunderbolt: `curl http://10.10.10.1:11434/api/tags`
- [x] AmneziaVPN installed on both minis
- [x] VPN configs imported and connected on both minis
- [x] Moonshot API key saved on M4 (`~/.config/axinova/moonshot.env`)
- [x] **Vikunja access via SSH tunnel** (GFW blocks SNI to vikunja.axinova-internal.xyz; SSH tunnel to 121.40.188.25:3456 bypasses it)
- [x] SSH tunnel launchd plist deployed (`com.axinova.vikunja-tunnel.plist`) on both minis
- [x] **Ollama tunnel plist created** (`com.axinova.ollama-tunnel.plist`) — M4 localhost:11434 → M2 Pro via Thunderbolt
- [x] Ollama tunnel active on M4 (existing SSH session, plist deferred — port already in use)

---

## Phase 3: Agent Runtime

- [x] Create `scripts/agent-launcher.sh` (Vikunja poller + Codex CLI executor)
- [x] Rewrite agent-launcher.sh: direct Vikunja API (no LLM for task mgmt), Codex for coding
- [x] **Phase 2 rewrite: multi-model execution** (Codex CLI → Kimi K2.5 → Ollama fallback)
- [x] **Secret loading from `~/.config/axinova/*.env`** (not plist env vars)
- [x] **Kimi K2.5 API integration** (Moonshot, OpenAI-compatible)
- [x] **Ollama local inference integration**
- [x] **Model selection heuristic** (simple tasks → Ollama, others → Kimi)
- [x] **Unified diff protocol** for text-only LLMs (extract diff, `git apply --index`)
- [x] **Vikunja task comments** (audit trail: CLAIMED → STARTED → COMPLETED/BLOCKED)
- [x] **Per-agent Discord identity** (username + avatar per role)
- [x] **Rich Discord embeds** (model used, duration, PR link as embed fields)
- [x] Create role instruction files in `agent-instructions/`
- [x] Create launchd plists for all 5 agents + OpenClaw
- [x] Update plists: agent01 for M4, focusagent02 for M2 Pro
- [x] Add Vikunja env vars to all plists
- [x] **Add OLLAMA_HOST to all plists**
- [x] Deploy plists to ~/Library/LaunchAgents on both machines
- [x] Update plists: Vikunja URL → `http://localhost:3456` (SSH tunnel)
- [x] Agent-launcher tested: polls Vikunja successfully, finds "No tasks" (correct)
- [x] Deploy updated agent-launcher.sh to both machines
- [x] Deploy Moonshot API key to M2 Pro (`~/.config/axinova/moonshot.env`)
- [x] **Load launchd agents** — all 5 agents running (2 on M4, 3 on M2 Pro)
- [x] **Auto-commit safety net** — catches when Codex CLI modifies files but can't commit (sandbox restriction)
- [x] **Vikunja comments API** — confirmed PUT method works for creating comments (not POST)
- [x] **E2E Test #1 PASSED** — Task #115 "Add /v1/version endpoint":
  - Agent claimed within 2-min poll cycle
  - Codex CLI (gpt-5.3-codex) created handler, test, wired route
  - Auto-commit triggered (Codex sandbox blocked git)
  - PR #16 created: https://github.com/axinova-ai/axinova-home-go/pull/16
  - Vikunja comments: `[CLAIMED]` → `[STARTED]` → `[COMPLETED]` with PR link
  - Duration: 1m52s, Model: codex-cli

---

## Phase 4: OpenClaw + Discord

- [x] Create `openclaw/setup.sh`
- [x] Update openclaw.json for multi-agent + multi-provider (Moonshot, OpenRouter, Ollama)
- [x] Update task-router-prompt.md with `/status`, `/assign`, `/models` commands
- [x] Install OpenClaw v2026.2.26 on M4 (`npm install -g openclaw@latest`)
- [x] Configure via `openclaw doctor --fix` (auto-detects DISCORD_BOT_TOKEN from env)
- [x] Model configured: `openai/kimi-k2.5` via Moonshot API (OPENAI_API_KEY → MOONSHOT_API_KEY)
- [x] Created `scripts/openclaw-start.sh` wrapper (sources env files before starting gateway)
- [x] Updated openclaw plist to use wrapper script
- [x] OpenClaw gateway running — Discord bot logged in
- [x] Connect Discord bot — `@Axinova Agent Bot` online
- [ ] Test: Discord message → Vikunja task → agent → PR → notification

---

## Phase 5: Local Console Bot (Discord → Ollama)

A thin Node.js Discord bot that lets you interact with M2 Pro's Ollama LLM server directly from Discord. Runs on M4 (where localhost:11434 is tunneled to M2 Pro via SSH over Thunderbolt).

### Implementation
- [x] `integrations/discord-local-console/package.json` — discord.js v14
- [x] `integrations/discord-local-console/lib/logger.js` — JSON lines to stdout + file
- [x] `integrations/discord-local-console/lib/routing.js` — Canonical alias SSoT, atomic JSON persistence
- [x] `integrations/discord-local-console/lib/ollama.js` — Ollama HTTP client (native fetch, 120s timeout)
- [x] `integrations/discord-local-console/commands/ping.js` — `!ping` / `!ping local`
- [x] `integrations/discord-local-console/commands/models.js` — `!models` / `!model <alias>`
- [x] `integrations/discord-local-console/commands/ask.js` — `!ask <prompt>` with single-flight, rate limit, typing refresh, file attach
- [x] `integrations/discord-local-console/commands/status.js` — `!status` fleet health
- [x] `integrations/discord-local-console/commands/help.js` — `!help` command listing
- [x] `integrations/discord-local-console/index.js` — Discord client, command dispatch, graceful shutdown
- [x] `scripts/local-console/local-console-start.sh` — Sources env, exec node
- [x] `scripts/local-console/install.sh` — npm ci, env stub, launchd plist install
- [x] `scripts/local-console/uninstall.sh` — Unload plist, cleanup
- [x] `launchd/com.axinova.local-console-bot.plist` — RunAtLoad, KeepAlive on failure, ThrottleInterval 30
- [x] `docs/runbooks/local-console-bot.md` — Setup, commands, troubleshooting
- [x] `README.md` — Updated architecture diagram + repo structure

### Deployment & Testing
- [x] Discord bot app created (Axinova Console#1544)
- [x] Bot invited to guild
- [x] npm install — discord.js installed, all modules load cleanly
- [x] Bot connects to Discord successfully (1 guild)
- [x] **Enable Message Content Intent** in Discord Developer Portal
- [x] **Fix: Add `DirectMessages` intent + `Partials.Channel`** — bot was only listening for guild messages, DMs were silently dropped
- [x] Test `!ping` → bot responds (confirmed via DM)
- [ ] Test `!ping local` → Ollama health check
- [ ] Test `!models` → list aliases
- [ ] Test `!model local-code` → set channel default, verify persistence
- [ ] Test `!ask "write a Go http handler"` → Ollama response (requires tunnel)
- [ ] Test `!status` → fleet health
- [ ] Test concurrent `!ask` → second request rejected ("Busy")
- [ ] Deploy to M4 via `scripts/local-console/install.sh`
- [ ] Verify launchd persistence (restart survives)

### Key Design
- **Routing SSoT**: `~/.config/axinova/local-console-routing.json` — alias map + channel/user defaults
- **Default aliases**: `local-general` → `qwen2.5:7b-instruct`, `local-code` → `qwen2.5-coder:7b`
- **Guardrails**: 5 req/60s per user, single-flight per channel, 120s timeout, >2000 chars → file attachment
- **Security**: Token from `~/.config/axinova/discord-local-console.env` (chmod 600), never in plist

---

## Phase 6: GitHub & CI/CD Updates

- [ ] Update CI workflows to exclude `agent/**` branches
- [ ] Configure branch protection on `main`
- [ ] Verify: agent branch push → no Actions, PR → CI runs

---

## Phase 6: End-to-End Tests

- [x] **Test 1: Vikunja → Codex CLI → PR → Vikunja comments** — PASSED (Task #115, PR #16, 1m52s)
- [ ] Test 2: Discord → OpenClaw → Vikunja → agent → full lifecycle
- [ ] Test 3: Simple task → routes to Ollama → completes locally → zero cloud cost
- [x] Test 4: Codex CLI path → ChatGPT auth → native execution → PR — PASSED (gpt-5.3-codex model)
- [ ] Success criteria:
  - Discord to PR: under 15 min
  - PR has tests, follows conventions
  - Full audit trail in Vikunja comments
  - No API keys in plist files

---

## Blockers

| Blocker | Impact | Resolution |
|---------|--------|------------|
| ~~Vikunja unreachable from Mac Minis~~ | ~~Agents can't poll tasks~~ | **RESOLVED** — SSH tunnel bypass (GFW SNI inspection was blocking TLS) |
| ~~Codex CLI model availability~~ | ~~`codex-mini` not available~~ | **RESOLVED** — `gpt-5.3-codex` works via ChatGPT auth |
| ~~Vikunja comments API method~~ | ~~Comments not posting~~ | **RESOLVED** — Vikunja uses PUT (not POST) for creating comments |
| ~~Codex CLI not committing~~ | ~~Changes left on working tree~~ | **RESOLVED** — Added auto-commit safety net in agent-launcher.sh |
| Gemma 3 4B download fails | Minor — Qwen 2.5 Coder 7B already installed as alternative | Retry later (IPv6 routing through VPN) |

---

## Files Changed

### Phase 2 (Mar 2, 2026 — Multi-model + Audit Trail)

| File | Change |
|------|--------|
| `scripts/agent-launcher.sh` | Multi-model execution (Codex → Kimi → Ollama), unified diff protocol, Vikunja comments, secret loading from env files, per-agent Discord identity, rich embeds |
| `scripts/fleet-status.sh` | Agent ledger (Vikunja comments), Ollama tunnel check, secrets check, LLM model chain display |
| `scripts/benchmark-ollama.sh` | **NEW** — Local LLM benchmark (qwen2.5-coder:7b vs gemma3:4b) |
| `openclaw/openclaw.json` | Multi-agent + multi-provider (Moonshot, OpenRouter, Ollama), worker agents defined |
| `openclaw/task-router-prompt.md` | `/status`, `/assign`, `/models` commands, agent fleet table, DM support, communication protocol |
| `launchd/com.axinova.agent-*.plist` (×5) | Added `OLLAMA_HOST` env var |
| `launchd/com.axinova.openclaw.plist` | Added `OLLAMA_HOST` env var |
| `launchd/com.axinova.ollama-tunnel.plist` | **NEW** — SSH tunnel M4 localhost:11434 → M2 Pro 10.10.10.1:11434 via Thunderbolt |
| `PROGRESS.md` | Full Phase 2 status update |
| `README.md` | Updated architecture, LLM strategy, repo structure |
| `IMPLEMENTATION.md` | Added Phase 2.5 (multi-model), Phase 3.5 (OpenClaw multi-agent), deployment steps |

### Phase 1 (Mar 2, 2026 — Initial Setup)

| File | Change |
|------|--------|
| `README.md` | Updated architecture diagram for Codex CLI, Kimi K2.5 |
| `docs/AGENT_TEAMS.md` | Updated runtime section: claude -p → Codex CLI |
| `IMPLEMENTATION.md` | Updated auth section, troubleshooting for Codex/Vikunja API |

### Deployed to Machines

| Target | Files |
|--------|-------|
| M4 (agent01) | `com.axinova.agent-backend-sde.plist`, `com.axinova.agent-frontend-sde.plist` → ~/Library/LaunchAgents/ |
| M2 Pro (focusagent02) | `com.axinova.agent-devops.plist`, `com.axinova.agent-qa.plist`, `com.axinova.agent-tech-writer.plist` → ~/Library/LaunchAgents/ |

### Phase 2.5 (Mar 2, 2026 — Deployment + E2E)

| Target | Action |
|--------|--------|
| Both machines | Deployed fixed `agent-launcher.sh` (PUT for comments, auto-commit safety net) |
| M2 Pro | Deployed `moonshot.env` for Kimi K2.5 access |
| M4 | Installed OpenClaw v2026.2.26, created `scripts/openclaw-start.sh` wrapper |
| M4 | Updated `com.axinova.openclaw.plist` to use wrapper script |
| Both machines | All 5 agents + OpenClaw loaded and running |
| E2E | Task #115 → Codex CLI → PR #16 → full audit trail in Vikunja comments

### Phase 5 (Mar 2, 2026 — Local Console Bot)

| File | Change |
|------|--------|
| `integrations/discord-local-console/` | **NEW** — Discord bot gateway for Ollama (package.json, index.js, commands/*, lib/*) |
| `scripts/local-console/` | **NEW** — Start, install, uninstall scripts |
| `launchd/com.axinova.local-console-bot.plist` | **NEW** — LaunchAgent for M4 |
| `docs/runbooks/local-console-bot.md` | **NEW** — Operational runbook |
| `README.md` | Added Local Console Bot to architecture diagram + repo structure |
| `PROGRESS.md` | Added Phase 5 tracking |

---

## Deferred

| Item | When |
|------|------|
| Tailscale mesh | Deferred — SSH tunnels work well enough |
| LiteLLM gateway on M2 Pro | After basic setup stable |
| Gemma 3 4B model | After VPN IPv6 stable |
| deepseek-coder-v2:16b-lite | After benchmark results |
| AI Research agent | Month 2 |
| Grafana agent dashboard | Month 2 |
| Auto-merge for tests/docs | Month 2 |
| Daily standup automation | Month 2 |
