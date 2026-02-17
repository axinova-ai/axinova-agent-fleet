# Agent Fleet Implementation Progress

Last Updated: 2026-02-17

## Overview

**Goal:** Two Mac minis running 5 specialized AI agents that autonomously handle software development via Claude Code CLI, coordinated through Vikunja tasks and Discord.

**Timeline:** 6 phases over ~2 days (12 hours total), then continuous operation.

**Current Status:** Phase 0-3 scripts ready, pending physical deployment.

---

## Phase 0: Pre-flight Preparation (30 min)

- [ ] Create GitHub bot account: `axinova-fleet-bot`
  - [ ] Add to `axinova-ai` org as Member
  - [ ] Fine-grained PAT: contents:write, pull_requests:write, issues:write, metadata:read
  - [ ] Store token in 1Password
- [ ] Gather MCP tokens from 1Password (Portainer, Grafana, SilverBullet, Vikunja)
- [ ] Create Discord bot via Developer Portal → save token
- [ ] Set up Vikunja project "Agent Fleet" with labels:
  - `backend-sde` (green), `frontend-sde` (blue), `devops` (orange)
  - `qa` (yellow), `docs` (purple), `urgent` (red), `blocked` (gray)

---

## Phase 1: Mac Mini Bootstrap (2 hours)

### Per Machine
- [ ] Physical setup, create admin user `weixia`, enable Remote Login + Screen Sharing
- [ ] Run `bootstrap/mac/setup-macos.sh` (installs Homebrew, Go, Node, Docker, Claude Code, tmux)
- [ ] Configure Claude Code: `export ANTHROPIC_API_KEY=<key> && claude auth login`
- [ ] Configure GitHub: `gh auth login --with-token`, set git identity to `axinova-fleet-bot`
- [ ] Copy MCP config to `~/.claude/settings.json` with actual tokens
- [ ] Clone all `axinova-*` repos to `~/workspace/`

### Verification Checklist
- [ ] `claude --version` works
- [ ] `claude -p "Use vikunja_list_projects"` returns data
- [ ] `go version` → 1.24+, `node --version` → 22+, `docker --version` works
- [ ] `gh auth status` → logged in as `axinova-fleet-bot`

---

## Phase 2: AmneziaWG VPN + Thunderbolt (1 hour)

- [ ] Install AmneziaWG: `brew install --cask amneziawg`
- [ ] Import configs from `vpn-distribution/configs/macos/`:
  - M4: `m4-agent-1.conf` (10.66.66.3)
  - M2 Pro: `m2-pro-agent-2.conf` (10.66.66.2)
- [ ] Enable auto-connect on login in AmneziaWG app
- [ ] Thunderbolt Bridge: M4=169.254.100.1/24, M2 Pro=169.254.100.2/24
- [ ] Verify: ping VPN server (10.66.66.1), each other, internal services

---

## Phase 3: Agent Runtime (3 hours)

- [x] Create `scripts/agent-launcher.sh` (Vikunja poller + claude -p executor)
- [x] Create role instruction files in `agent-instructions/`:
  - [x] `backend-sde.md`
  - [x] `frontend-sde.md`
  - [x] `devops.md`
  - [x] `qa-testing.md`
  - [x] `tech-writer.md`
- [x] Create launchd plists in `launchd/` for all 5 agents + OpenClaw
- [ ] Deploy to M4: backend-sde, frontend-sde agents
- [ ] Deploy to M2 Pro: devops, qa, tech-writer agents
- [ ] Test: create Vikunja task → agent picks up → PR created

---

## Phase 4: OpenClaw + Discord (2 hours)

- [x] Create `openclaw/setup.sh`
- [ ] Install OpenClaw on M4
- [ ] Connect Discord bot
- [ ] Configure command routing (/task, /status, /deploy)
- [ ] Set up Discord channel notifications (#agent-tasks, #agent-prs, #agent-alerts, #agent-logs)
- [ ] Test: Discord message → Vikunja task → agent → PR → notification

---

## Phase 5: GitHub & CI/CD Updates (1 hour)

- [ ] Update CI workflows to exclude `agent/**` branches
- [ ] Configure branch protection on `main` (require PR + 1 approval + CI)
- [ ] Verify: agent branch push → no Actions, PR → CI runs

---

## Phase 6: End-to-End Test (2 hours)

- [ ] Full flow: Discord → Vikunja → agent → PR → review → merge → deploy
- [ ] Success criteria:
  - Discord to PR: under 15 min
  - PR has tests, follows conventions
  - No wasted GitHub Actions minutes
  - Full audit trail in Vikunja + SilverBullet + GitHub

---

## Files Changed (Feb 17, 2026)

### Modified
| File | Change |
|------|--------|
| `bootstrap/mac/Brewfile` | amneziawg cask, tmux; removed wireguard-tools |
| `bootstrap/mac/setup-macos.sh` | Claude Code install, updated next steps |
| `integrations/mcp/agent-mcp-config.json` | Fixed path, token templates, permissions |
| `README.md` | New architecture, AmneziaWG, agent workflow |
| `PROGRESS.md` | Full rewrite with new 6-phase plan |

### Created
| File | Purpose |
|------|---------|
| `scripts/agent-launcher.sh` | Core polling + execution script |
| `agent-instructions/backend-sde.md` | Backend SDE Claude instructions |
| `agent-instructions/frontend-sde.md` | Frontend SDE Claude instructions |
| `agent-instructions/devops.md` | DevOps Claude instructions |
| `agent-instructions/qa-testing.md` | QA & Testing Claude instructions |
| `agent-instructions/tech-writer.md` | Tech Writer Claude instructions |
| `launchd/com.axinova.agent-backend-sde.plist` | macOS daemon |
| `launchd/com.axinova.agent-frontend-sde.plist` | macOS daemon |
| `launchd/com.axinova.agent-devops.plist` | macOS daemon |
| `launchd/com.axinova.agent-qa.plist` | macOS daemon |
| `launchd/com.axinova.agent-tech-writer.plist` | macOS daemon |
| `launchd/com.axinova.openclaw.plist` | OpenClaw daemon |
| `bootstrap/vpn/amneziawg-setup.sh` | AmneziaWG config import |
| `openclaw/setup.sh` | OpenClaw + Discord setup |

### Deleted
| File | Reason |
|------|--------|
| `bootstrap/vpn/wireguard-install.sh` | Replaced by AmneziaWG |
| `bootstrap/vpn/wg0.conf.template` | Old WireGuard template |
| `bootstrap/vpn/connect-sg.sh` | Uses wg-quick, not needed with AmneziaWG app |
| `integrations/mcp/mcp-client-example.go` | Claude Code has native MCP |

---

## Deferred

| Item | When |
|------|------|
| AI Research agent | Month 2 |
| Grafana agent dashboard | Month 2 |
| Auto-merge for tests/docs | Month 2 |
| Daily standup automation | Month 2 |
| WhatsApp integration | Later |
