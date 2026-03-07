# Agent Fleet Visual Overview

## System Architecture (as of 2026-03-07)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Wei's M1 MacBook Air (10.66.66.18) — PRIMARY ACCESS                    │
│  Daily coding machine                                                    │
│                                                                          │
│  • Claude Code (local) — full dev environment                           │
│  • Direct SSH to M4/M2 Pro via VPN                                      │
│  • Hands-on coding, PR review, task creation                            │
│  • Git operations across all repos                                      │
└─────────────────────────────────────────────────────────────────────────┘
           │                              │
           │ SSH / VPN                    │ VPN (10.66.66.0/24)
           ▼                              ▼
┌────────────────────────┐   ┌──────────────────────────────────────────────┐
│  M1 Workstation        │   │  M4 Mac Mini (agent01) — 10.66.66.3         │
│  10.66.66.4 (planned)  │   │  Command Center + SDEs                      │
│                        │   │                                              │
│  • Remote mirror of    │   │  ┌────────────────────────────────────────┐  │
│    M1 MacBook Air      │   │  │  OpenClaw Discord Bot                  │  │
│  • Claude Code tunnel  │   │  │  Discord → Vikunja task routing        │  │
│    for phone access    │   │  │  SOCKS5 proxy → Singapore (GFW bypass)│  │
│  • Limited permissions │   │  └────────────────────────────────────────┘  │
│  • Task planning only  │   │                                              │
└────────────────────────┘   │                                              │
                             │  ┌──────────────────────────────────────┐    │
                             │  │  Backend SDE Agents (×6)             │    │
                             │  │  • axinova-home-go                   │    │
                             │  │  • axinova-ai-lab-go                 │    │
                             │  │  • axinova-miniapp-builder-go        │    │
                             │  │  • axinova-trading-agent-go          │    │
                             │  │  • axinova-ai-social-publisher-go    │    │
                             │  │  • axinova-mcp-server-go             │    │
                             │  └──────────────────────────────────────┘    │
                             │                                              │
                             │  ┌──────────────────────────────────────┐    │
                             │  │  Frontend SDE Agents (×4)            │    │
                             │  │  • axinova-home-web                  │    │
                             │  │  • axinova-trading-agent-web         │    │
                             │  │  • axinova-miniapp-builder-web       │    │
                             │  │  • axinova-ai-social-publisher-web   │    │
                             │  └──────────────────────────────────────┘    │
                             │                                              │
                             │  Codex CLI + Local Console Bot               │
                             └──────────────────────────────────────────────┘
                                              │
                                              │ AmneziaWG VPN
                                              │ (10.66.66.0/24)
                                              │
┌──────────────────────────────────────────────┼────────────────────────────┐
│  M2 Pro Mac Mini (focusagent02) — 10.66.66.2 │                            │
│  Ops + QA + Wiki                             │                            │
│                                              │                            │
│  ┌──────────────────────────────────────┐    │  ┌──────────────────────┐  │
│  │  DevOps Agent                       │    │  │  VPN Server          │  │
│  │  • axinova-deploy                   │    │  │  8.222.187.10        │  │
│  └──────────────────────────────────────┘    │  │  Singapore Aliyun    │  │
│                                              │  │                      │  │
│  ┌──────────────────────────────────────┐    │  │  • AmneziaWG         │  │
│  │  QA Testing Agent                   │    │  │    (amneziawg-go)    │  │
│  │  • axinova-home-go                  │    │  │  • Port: 39999       │  │
│  └──────────────────────────────────────┘    │  │    (stable relay)   │  │
│                                              │  │  • SOCKS5 relay      │  │
│  ┌──────────────────────────────────────┐    │  │    for GFW bypass   │  │
│  │  Tech Writer Agent                  │    │  │  • 15 VPN peers      │  │
│  │  • SilverBullet wiki               │    │  └──────────────────────┘  │
│  └──────────────────────────────────────┘    │                            │
│                                              │                            │
│  Codex CLI + Ollama (local LLM)              │                            │
└──────────────────────────────────────────────┴────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────┐
              │      GitHub              │
              │  axinova-ai org          │
              │  • PRs from agents       │
              │  • CI on merge to main   │
              └──────────────────────────┘
```

## Task Flow: Discord → Code → PR

```
Wei sends Discord message: "Add user profile page to home-web"
    │
    ▼
OpenClaw (M4) — task-router agent
    │  Parses intent, determines role + repo
    ▼
Vikunja task created:
    │  Title: "Add user profile page"
    │  Label: frontend-sde
    │  Project: axinova-home-web
    ▼
Frontend SDE agent-launcher (M4) polls Vikunja
    │  Finds task with label "frontend-sde"
    │  Claims task (percent_done=0.5)
    ▼
Codex CLI executes in axinova-home-web/
    │  Reads: agent-instructions/frontend-sde.md
    │  Creates: src/views/ProfileView.vue
    │  Runs: npm run build (type check + bundle)
    ▼
Git operations:
    │  Branch: agent/frontend-sde/task-<id>
    │  Commit + push
    │  gh pr create
    ▼
Vikunja task marked done with PR URL
    │
    ▼
Wei reviews PR on phone → merge → GitHub Actions CI → deploy
```

## Task Flow: M1 MacBook Air → Claude Code → Agent Fleet (primary)

The most productive route. Wei uses Claude Code on the M1 MacBook Air
to directly access the entire fleet — SSH into M4/M2 Pro, create tasks,
review PRs, and do hands-on coding.

```
Wei's M1 MacBook Air (10.66.66.18) — Daily Coding Machine
    │
    │  Claude Code (local session)
    │  Full dev environment + VPN access to all machines
    ▼
┌─────────────────────────────────────────────┐
│  Option A: Create Vikunja task directly     │
│  curl -X POST vikunja.axinova-internal.xyz  │
│  → Agent-launcher picks up automatically   │
│                                             │
│  Option B: Send Discord message             │
│  → OpenClaw routes to correct agent         │
│                                             │
│  Option C: Direct git operations            │
│  git commit, gh pr create, code review      │
│  → Hands-on coding via Claude Code          │
│                                             │
│  Option D: SSH into M4/M2 Pro              │
│  ssh agent01 / ssh focusagent02             │
│  → Direct fleet management                 │
└─────────────────────────────────────────────┘
```

## Task Flow: Phone → M1 Workstation → Agent Fleet (mobile)

When Wei is away from the MacBook (e.g., during day job 10am-6pm),
the M1 Workstation serves as a remote mirror with only the permissions
needed for task planning and fleet management — not a full dev machine.

```
Wei's Phone (iPhone / Android)
    │
    │  Claude Code tunnel / SSH
    ▼
M1 Workstation (10.66.66.4) — Remote Mirror
    │  Mirror of M1 MacBook Air setup
    │  Limited to: task creation, PR review, fleet oversight
    │  Not a full dev environment — just remote hands
    ▼
Create Vikunja tasks / Discord messages / review PRs
    │
    ├──→ OpenClaw (M4) ──→ Routes to appropriate agent
    ├──→ M4 agent-launchers (10 SDEs) ──→ Backend + Frontend PRs
    └──→ M2 agent-launchers (3 ops) ──→ DevOps + QA + Wiki
```

## Machine Inventory

| Machine | VPN IP | Role | Services | LLM Runtime |
|---------|--------|------|----------|-------------|
| M1 MacBook Air | 10.66.66.18 | **Primary dev machine** | Claude Code (local), full dev env, fleet access | Claude Code |
| M4 Mac Mini | 10.66.66.3 | Command + SDEs | OpenClaw, 6 backend SDEs, 4 frontend SDEs, console bot | Codex CLI (OpenAI) |
| M2 Pro Mac Mini | 10.66.66.2 | Ops + QA + Wiki | DevOps, QA testing, tech writer agents | Codex CLI + Ollama |
| M1 Workstation | 10.66.66.4 | Remote mirror (planned) | Claude Code tunnel for phone access, limited permissions | Claude Code |
| VPN Server | 8.222.187.10 | Network hub | AmneziaWG, SOCKS5 relay | — |

## Agent Summary

| Agent Role | Machine | Repos | Poll Interval | Launchd Service |
|------------|---------|-------|--------------|-----------------|
| backend-sde ×6 | M4 | home-go, ai-lab-go, miniapp-builder-go, trading-agent-go, ai-social-publisher-go, mcp-server-go | 120s | com.axinova.agent-backend-sde-{1-6} |
| frontend-sde ×4 | M4 | home-web, trading-agent-web, miniapp-builder-web, ai-social-publisher-web | 120s | com.axinova.agent-frontend-sde-{1-4} |
| devops | M2 Pro | axinova-deploy | 120s | com.axinova.agent-devops |
| qa-testing | M2 Pro | axinova-home-go | 120s | com.axinova.agent-qa |
| tech-writer | M2 Pro | axinova-agent-fleet (SilverBullet wiki) | 180s | com.axinova.agent-tech-writer |

## VPN Network

```
10.66.66.0/24 (AmneziaWG, obfuscated)

  .1  — VPN Server (Singapore)
  .2  — M2 Pro Mac Mini (focusagent02)
  .3  — M4 Mac Mini (agent01)
  .4  — M1 Workstation (planned)
  .10 — Wei's iPhone
  .11 — Lisha's MacBook Air
  .12 — Wei's MacBook Pro
  .13 — Wei's HP Windows
  .14 — Wei's Xiaomi Ultra 14
  .15 — Lisha's iPhone
  .16 — Lisha's MacBook Air (Wei's account)
  .17 — Lisha's Dell Windows
  .18 — Wei's M1 MacBook Air
  .19 — Hua's iPhone
  .20 — Hua's Windows
  .21 — Wei's Moto One Ace

Stable relay port: UDP 39999 (iptables DNAT → internal AWG port)
GFW bypass: AmneziaWG obfuscation + port rotation via rotate-vpn-port.sh
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `scripts/agent-launcher.sh` | Core agent runtime — polls Vikunja, runs Codex, creates PRs |
| `scripts/openclaw-start.sh` | OpenClaw launcher with SOCKS5 GFW bypass |
| `scripts/proxy-bootstrap.cjs` | Node.js SOCKS5 proxy interceptor (no npm deps) |
| `scripts/rotate-vpn-port.sh` | Rotate VPN internal port (zero client changes) |

## Cost Model

```
Monthly Infrastructure:
  Aliyun SAS (VPN server):    ~$5/month
  Mac Mini M4 (electricity):  ~$3/month
  Mac Mini M2 Pro:            ~$3/month
  Mac Mini M1 (planned):      ~$3/month

Monthly API:
  OpenAI Codex CLI:           ~$30-50/month (10 agents × task volume)
  Moonshot/Kimi (OpenClaw):   ~$5-10/month (task routing only)

Total:                        ~$50-75/month for 13 autonomous agents
```
