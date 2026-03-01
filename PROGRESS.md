# Agent Fleet Implementation Progress

Last Updated: 2026-03-02

## Overview

**Goal:** Two Mac minis running 5 specialized AI agents that autonomously handle software development, coordinated through Vikunja tasks and Discord.

**LLM Strategy (native CLIs, no abstraction layers):**

| Tier | Provider | CLI | Use Case |
|------|----------|-----|----------|
| Routing | Kimi K2.5 (Moonshot) | OpenClaw native | Task routing from Discord → Vikunja |
| Coding | OpenAI Codex | `codex` CLI native | Primary autonomous coding agent |
| Simple | Qwen 2.5 7B (Ollama) | Local inference | Routine tasks (docs, lints, simple fixes) |
| Review | Claude (Anthropic) | `claude` CLI (human) | PR review + merge (human-in-the-loop) |

**Machine Architecture:**

| Machine | Role | Tools | Network |
|---------|------|-------|---------|
| MacBook Air (192.168.3.44) | Human dev | Claude Code (Pro Max) | Wi-Fi + Tailscale |
| M4 Mac Mini (192.168.3.6, `agent01`) | Agent runner + OpenClaw | Codex CLI, OpenClaw + Kimi | Wi-Fi + Thunderbolt (10.10.10.2) + Tailscale (pending) |
| M2 Pro Mac Mini (192.168.3.5, `focusagent02`) | LLM server + agents | Codex CLI, Ollama (Qwen) | Wi-Fi + Thunderbolt (10.10.10.1) + Tailscale (pending) |

**Current Status:** Both machines bootstrapped. Codex CLI installed + authenticated. All repos cloned. Plists deployed but not loaded (blocked on Tailscale for Vikunja access). Docs updated for Codex CLI architecture.

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
- [ ] Tailscale logged in (required for Vikunja access)

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
- [ ] Tailscale logged in (required for Vikunja access)
- [ ] Pull Gemma 3 4B (blocked by VPN IPv6 routing, defer to Tailscale)

### Verification Checklist
- [x] `claude --version` works on both machines → v2.1.49
- [x] `codex --version` works on both machines → v0.106.0
- [x] `codex` auth (OpenAI login) on both machines ✓
- [x] `go version` → 1.24+, `node --version` → 22+
- [x] `gh auth status` → logged in as `harryxiaxia` on both

---

## Phase 2: Thunderbolt Bridge + VPN

- [x] Thunderbolt Bridge: M4=10.10.10.2, M2 Pro=10.10.10.1 (sub-ms latency)
- [x] Ollama on M2 Pro listening on 0.0.0.0:11434 (PlistBuddy fix + custom plist backup)
- [x] M4 can reach Ollama via Thunderbolt: `curl http://10.10.10.1:11434/api/tags` ✓
- [x] AmneziaVPN installed on both minis
- [x] VPN configs imported and connected on both minis
- [x] Moonshot API key saved on M4 (`~/.config/axinova/moonshot.env`)
- [ ] **Tailscale setup on both minis** (required — Vikunja is only reachable via Tailscale mesh)

---

## Phase 3: Agent Runtime

- [x] Create `scripts/agent-launcher.sh` (Vikunja poller + Codex CLI executor)
- [x] Rewrite agent-launcher.sh: direct Vikunja API (no LLM for task mgmt), Codex for coding
- [x] Create role instruction files in `agent-instructions/`
- [x] Create launchd plists for all 5 agents + OpenClaw
- [x] Update plists: agent01 for M4, focusagent02 for M2 Pro
- [x] Add Vikunja env vars to all plists
- [x] Deploy plists to ~/Library/LaunchAgents on both machines
- [x] Update docs (README, AGENT_TEAMS, IMPLEMENTATION) for Codex CLI architecture
- [ ] **Load launchd agents** (blocked on Tailscale — Vikunja unreachable without it)
- [ ] Test: create Vikunja task → agent picks up → PR created

---

## Phase 4: OpenClaw + Discord

- [x] Create `openclaw/setup.sh`
- [x] Update openclaw.json for Kimi K2.5 model
- [ ] Install OpenClaw on M4
- [ ] Connect Discord bot
- [ ] Test: Discord message → Vikunja task → agent → PR → notification

---

## Phase 5: GitHub & CI/CD Updates

- [ ] Update CI workflows to exclude `agent/**` branches
- [ ] Configure branch protection on `main`
- [ ] Verify: agent branch push → no Actions, PR → CI runs

---

## Phase 6: End-to-End Test

- [ ] Full flow: Discord → Vikunja → agent → PR → review → merge → deploy
- [ ] Success criteria:
  - Discord to PR: under 15 min
  - PR has tests, follows conventions
  - Full audit trail

---

## Blockers

| Blocker | Impact | Resolution |
|---------|--------|------------|
| **Tailscale not logged in on Mac Minis** | Vikunja API unreachable → agents can't poll tasks | Log in Tailscale on both machines (requires GUI) |
| Gemma 3 4B download fails | Minor — Qwen 2.5 Coder 7B already installed as alternative | Retry after Tailscale is up |

---

## Files Changed (Mar 2, 2026)

### Modified
| File | Change |
|------|--------|
| `README.md` | Updated architecture diagram for Codex CLI, Kimi K2.5, Tailscale |
| `docs/AGENT_TEAMS.md` | Updated runtime section: claude -p → Codex CLI |
| `IMPLEMENTATION.md` | Updated auth section, troubleshooting for Codex/Vikunja API |
| `PROGRESS.md` | Full status update |

### Deployed to Machines
| Target | Files |
|--------|-------|
| M4 (agent01) | `com.axinova.agent-backend-sde.plist`, `com.axinova.agent-frontend-sde.plist` → ~/Library/LaunchAgents/ |
| M2 Pro (focusagent02) | `com.axinova.agent-devops.plist`, `com.axinova.agent-qa.plist`, `com.axinova.agent-tech-writer.plist` → ~/Library/LaunchAgents/ |

---

## Deferred

| Item | When |
|------|------|
| LiteLLM gateway on M2 Pro | After basic setup stable |
| Gemma 3 4B model | After Tailscale stable |
| AI Research agent | Month 2 |
| Grafana agent dashboard | Month 2 |
| Auto-merge for tests/docs | Month 2 |
| Daily standup automation | Month 2 |
