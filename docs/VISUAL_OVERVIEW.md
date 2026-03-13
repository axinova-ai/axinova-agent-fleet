# Agent Fleet Visual Overview

## Three-Tier Architecture (as of 2026-03-07)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FOUNDER (Wei)                                    │
│                                                                          │
│  ┌─────────────────────────────────┐  ┌──────────────────────────────┐  │
│  │ M1 MacBook Air (10.66.66.18)   │  │ M1 Workstation (10.66.66.4) │  │
│  │ PRIMARY — Daily coding machine │  │ MIRROR — Phone remote access │  │
│  │                                │  │ (planned)                    │  │
│  │ • Claude Code (local)          │  │ • Claude Code tunnel         │  │
│  │ • Full dev env + VPN access    │  │ • Limited permissions        │  │
│  │ • SSH to M4/M2 Pro             │  │ • Task planning + PR review  │  │
│  │ • Git ops across all repos     │  │ • Not a full dev machine     │  │
│  └────────────┬───────────────────┘  └──────────────┬───────────────┘  │
│               │                                      │                  │
│               │ Claude Code / MCP / Discord          │ Phone (10-6 job) │
└───────────────┼──────────────────────────────────────┼──────────────────┘
                │                                      │
                ▼                                      ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       ORCHESTRATOR                                       │
│                                                                          │
│  OpenClaw (on M4, Kimi K2.5 via Moonshot API — routing only)            │
│  • Receives high-level intent from Founder                               │
│  • Decomposes into atomic tasks (one PR each)                           │
│  • Labels for categorization (NOT routing)                               │
│  • Creates tasks in Vikunja Project 13                                   │
│  • Monitors stuck/blocked tasks                                          │
│                                                                          │
│  Entry points:                                                           │
│    Discord message → OpenClaw → Vikunja                                  │
│    Claude Code → MCP vikunja_create_task → Vikunja                       │
│    Vikunja web UI → direct task creation                                  │
└──────────────────────────────┬───────────────────────────────────────────┘
                               │
                    Vikunja Kanban (Project 13)
                    Tasks labeled by category
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       BUILDER POOL                                       │
│                                                                          │
│  ┌─ M4 Mac Mini (agent01, 10.66.66.3) ──────────────────────────────┐  │
│  │  10x Generic Builders (builder-1 to builder-10)                   │  │
│  │  Also runs: OpenClaw, Local Console Bot                           │  │
│  │  LLM: codex exec (gpt-5.4, automated) → Needs Founder on fail   │  │
│  └───────────────────────────────────────┬──────────────────────────┘  │
│                                          │ Thunderbolt Bridge           │
│  ┌─ M2 Pro Mac Mini (focusagent02, 10.66.66.2) ────────────────────┐  │
│  │  6x Generic Builders (builder-11 to builder-16)                   │  │
│  │  Ollama LLM Server (Qwen 2.5 Coder 7B)                          │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└──────────────────────────────┬───────────────────────────────────────────┘
                               │
                               ▼
                ┌──────────────────────────┐
                │      GitHub              │
                │  axinova-ai org          │
                │  • PRs from builders     │
                │  • CI on merge to main   │
                │  • Founder reviews/merges│
                └──────────────────────────┘
```

## Task Flow: Discord → OpenClaw → Builder (quick dispatch)

```
Wei sends Discord message: "Ship user profile feature with backend API and frontend page"
    │
    ▼
OpenClaw (Orchestrator, Kimi K2.5 for routing)
    │  Decomposes into atomic tasks, maximizes parallelism
    ▼
Vikunja tasks created simultaneously:
    │  #42 "[axinova-home-go] Add GET /api/v1/user/profile endpoint" — label: backend
    │  #43 "[axinova-home-go] Add PUT /api/v1/user/profile endpoint" — label: backend
    │  #44 "[axinova-home-web] Add user profile page with edit form" — label: frontend
    │  #45 "[axinova-home-go] Add user profile integration tests"   — label: backend, testing
    ▼
4 generic builders claim 4 tasks in parallel
    │  Each builder: detect repo from title → cd ~/workspace/<repo>
    │  Read builder.md instructions + repo CLAUDE.md
    │  Execute via codex exec --full-auto (→ Needs Founder on failure)
    │  Implement → test → commit
    ▼
agent-launcher.sh handles:
    │  Branch: agent/builder-N/task-<id>
    │  Push + gh pr create
    │  Mark Vikunja task done with PR URL
    ▼
Wei reviews 4 PRs → merge → GitHub Actions CI → deploy
```

## Task Flow: Claude Code → MCP → Builder (design-first)

```
Wei's M1 MacBook Air — Claude Code session
    │
    │  Design features locally, then delegate implementation
    ▼
vikunja_create_task via MCP (or curl Vikunja API)
    │  Create task with rich description + labels
    │  Title includes repo name: "[axinova-home-go] ..."
    ▼
Builder agent polls Vikunja → claims task → implements → PR
    ▼
Wei reviews PR in Claude Code → approve → merge
```

## Task Flow: Phone → M1 Workstation (mobile, planned)

```
Wei's Phone (during day job 10am-6pm)
    │
    │  Claude Code tunnel / SSH
    ▼
M1 Workstation (10.66.66.4) — Remote Mirror
    │  Limited to: task creation, PR review, fleet oversight
    ▼
Create Vikunja tasks / Discord messages → OpenClaw → Builders
```

## Key Design Principles

### Builders are generic
Every agent is identical — same code, same tools, same access to all repos. No specialization. A builder picks up any unclaimed task and figures out what to do from the task description.

### Labels are categories, NOT routing
Labels describe the type of work for reporting and filtering. They don't control which agent picks up a task.

| Label | Use for |
|-------|---------|
| `backend` | Go APIs, handlers, sqlc, migrations |
| `frontend` | Vue 3, TypeScript, PrimeVue, Tailwind |
| `devops` | Docker, Traefik, CI/CD, deployment |
| `infra` | Database setup, tooling, provisioning |
| `qa` | E2E testing, release sign-off |
| `testing` | Unit tests, integration tests, coverage |
| `tech-writer` | Wiki, runbooks, API docs |
| `docs` | READMEs, architecture docs |
| `urgent` | Priority flag |
| `blocked` | Needs human intervention |

### Orchestrator always creates Vikunja tasks
Whether the intent comes from Discord, Claude Code MCP, or the Vikunja UI — builders only consume from the Vikunja queue. OpenClaw decomposes Discord messages into Vikunja tasks. It never directly commands a builder.

### One task = one PR
The orchestrator decomposes work so each task is atomic and produces exactly one PR (or one wiki update for tech-writer tasks).

## Machine Inventory

| Machine | VPN IP | Role | Services | LLM |
|---------|--------|------|----------|-----|
| M1 MacBook Air | 10.66.66.18 | **Founder primary** | Claude Code CLI (local), full dev env, fleet access | Claude Code CLI (Sonnet/Opus 4.6) |
| M4 Mac Mini | 10.66.66.3 | Orchestrator + Builders | OpenClaw, 10 builders (1-10), Local Console Bot | codex exec (gpt-5.4) |
| M2 Pro Mac Mini | 10.66.66.2 | Builders + LLM Server | 6 builders (11-16), Ollama (Qwen 2.5 Coder 7B) | Codex CLI + Ollama |
| M1 Workstation | 10.66.66.4 | Founder mirror | Claude Code CLI for phone access | Claude Code CLI (Sonnet/Opus 4.6) |
| VPN Server | 8.222.187.10 | Network hub | AmneziaWG, SOCKS5 relay | — |

## Builder Agent Details

| Component | Details |
|-----------|---------|
| Count | 16 total: 10 on M4 (builder-1..10), 6 on M2 Pro (builder-11..16) |
| Instructions | `agent-instructions/builder.md` (universal) |
| LaunchAgent | `com.axinova.agent-builder-{1..10}` |
| Poll interval | 120s |
| LLM chain | codex exec (gpt-5.4) → Needs Founder → Codex CLI or Claude Code CLI |
| Repo detection | Scan task title for `axinova-*` pattern |
| Audit trail | Vikunja task comments: `[CLAIMED] → [STARTED] → [IN REVIEW]` |

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
| `scripts/agent-launcher.sh` | Core runtime — polls Vikunja, multi-model execution, audit trail |
| `scripts/fleet-status.sh` | Fleet health dashboard |
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
  OpenAI Codex CLI:           ~$30-50/month (10 builders x task volume)
  Moonshot/Kimi (OpenClaw):   ~$5-10/month (orchestrator routing only, removed from builders)

Total:                        ~$50-75/month for 16 autonomous builders
```
