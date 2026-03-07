# Agent Teams Structure

## Overview

The agent fleet runs across two Mac Minis, with a total of **13 autonomous agents** organized by function. Each agent runs as a macOS LaunchAgent, polling Vikunja for tasks and executing them via Codex CLI.

## Current Architecture (as of 2026-03-07)

```
┌─────────────────────────────────────────────────────────────────┐
│ Mac Mini M4 (agent01) — 10.66.66.3                              │
│ Command Center + Software Development Engineers                 │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────┐    │
│ │  OpenClaw Discord Bot                                    │    │
│ │  Discord → Vikunja task routing (via SOCKS5 GFW bypass)  │    │
│ └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────┐    │
│ │  Backend SDE Agents (×6)                                 │    │
│ │                                                          │    │
│ │  #1 axinova-home-go          #4 axinova-trading-agent-go │    │
│ │  #2 axinova-ai-lab-go        #5 axinova-ai-social-pub-go│    │
│ │  #3 axinova-miniapp-builder-go  #6 axinova-mcp-server-go│    │
│ └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────┐    │
│ │  Frontend SDE Agents (×4)                                │    │
│ │                                                          │    │
│ │  #1 axinova-home-web         #3 axinova-miniapp-builder  │    │
│ │  #2 axinova-trading-agent    #4 axinova-ai-social-pub    │    │
│ └──────────────────────────────────────────────────────────┘    │
│                                                                  │
│ Codex CLI + Local Console Bot                                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Mac Mini M2 Pro (focusagent02) — 10.66.66.2                     │
│ Operations + Quality Assurance + Documentation                   │
│                                                                  │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│ │   DevOps     │  │   QA &       │  │  Tech        │           │
│ │   Agent      │  │   Testing    │  │  Writer      │           │
│ │              │  │   Agent      │  │  Agent       │           │
│ │ axinova-     │  │              │  │              │           │
│ │ deploy       │  │ axinova-     │  │ SilverBullet │           │
│ │              │  │ home-go      │  │ wiki         │           │
│ └──────────────┘  └──────────────┘  └──────────────┘           │
│                                                                  │
│ Codex CLI + Ollama (local LLM)                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Implemented Agent Roles

### 1. Backend SDE (×6 instances on M4)

**Vikunja label:** `backend-sde`
**Repos:** One agent per backend repo (home-go, ai-lab-go, miniapp-builder-go, trading-agent-go, ai-social-publisher-go, mcp-server-go)

**Responsibilities:**
- Implement Go microservices and APIs (chi v5 router)
- Database schemas, migrations, sqlc queries
- Backend tests and benchmarks
- Security (auth, validation, rate limiting)

**Task workflow:**
1. Poll Vikunja for tasks with `backend-sde` label
2. Claim task → create branch `agent/backend-sde/task-<id>`
3. Run Codex CLI with `agent-instructions/backend-sde.md`
4. Run `make test` and `make fmt`
5. Commit, push, `gh pr create`
6. Mark task done with PR URL

**LaunchAgent:** `com.axinova.agent-backend-sde-{1-6}` (poll: 120s)

---

### 2. Frontend SDE (×4 instances on M4)

**Vikunja label:** `frontend-sde`
**Repos:** One agent per frontend repo (home-web, trading-agent-web, miniapp-builder-web, ai-social-publisher-web)

**Responsibilities:**
- Vue 3 SPAs with TypeScript (Composition API)
- Tailwind CSS + PrimeVue components
- Bundle optimization and code splitting
- Type checking (`npm run build` includes tsc)

**Task workflow:**
1. Poll Vikunja for tasks with `frontend-sde` label
2. Claim task → create branch `agent/frontend-sde/task-<id>`
3. Run Codex CLI with `agent-instructions/frontend-sde.md`
4. Run `npm run build` (type check + bundle)
5. Commit, push, `gh pr create`
6. Mark task done with PR URL

**LaunchAgent:** `com.axinova.agent-frontend-sde-{1-4}` (poll: 120s)

---

### 3. DevOps Agent (×1 on M2 Pro)

**Vikunja label:** `devops`
**Repo:** axinova-deploy

**Responsibilities:**
- Docker Compose deployments (dev/stage/prod)
- GitHub Actions CI/CD pipelines
- Traefik ingress and TLS
- Prometheus/Grafana monitoring
- Infrastructure automation

**LaunchAgent:** `com.axinova.agent-devops` (poll: 120s)

---

### 4. QA Testing Agent (×1 on M2 Pro)

**Vikunja label:** `qa-testing`
**Repo:** axinova-home-go (primary target)

**Responsibilities:**
- Write test suites (unit, integration, E2E)
- Security scanning (govulncheck, npm audit)
- Test coverage analysis
- Bug hunting and reproduction

**LaunchAgent:** `com.axinova.agent-qa` (poll: 120s)

---

### 5. Tech Writer Agent (×1 on M2 Pro)

**Vikunja label:** `tech-writer`
**Target:** SilverBullet wiki (wiki.axinova-internal.xyz)

**Responsibilities:**
- API documentation and runbooks
- Architecture diagrams and tutorials
- Keep docs up-to-date with code changes
- Agent activity logs

**Special path:** Instead of git PR workflow, uses `execute_wiki_task()` which calls SilverBullet REST API directly (`GET/PUT /.fs/<page>.md`).

**LaunchAgent:** `com.axinova.agent-tech-writer` (poll: 180s)

---

## Task Routing

### OpenClaw (Discord → Vikunja)

OpenClaw runs on M4 as the command interface. Wei sends a Discord message describing work to be done. OpenClaw:
1. Parses intent using Moonshot/Kimi K2.5
2. Determines the correct agent role and repo
3. Creates a Vikunja task with the appropriate label
4. Agent-launcher picks it up on the next poll cycle

### Direct Vikunja Task Creation

Tasks can also be created directly in Vikunja (via API or web UI) with the correct label. Agent-launchers poll every 120s and claim the highest-priority open task matching their role.

### Vikunja Labels → Agent Mapping

| Label | Agent | Machine | Repo(s) |
|-------|-------|---------|---------|
| `backend-sde` | Backend SDE | M4 | home-go, ai-lab-go, miniapp-builder-go, trading-agent-go, ai-social-publisher-go, mcp-server-go |
| `frontend-sde` | Frontend SDE | M4 | home-web, trading-agent-web, miniapp-builder-web, ai-social-publisher-web |
| `devops` | DevOps | M2 Pro | axinova-deploy |
| `qa-testing` | QA Testing | M2 Pro | axinova-home-go |
| `tech-writer` | Tech Writer | M2 Pro | SilverBullet wiki |
| `urgent` | All agents | Both | Escalation |
| `blocked` | None | — | Needs human intervention |

### Priority Mapping

| Priority | Handling |
|----------|----------|
| 5 (Critical) | All agents available for escalation |
| 4 (High) | M4 SDE agents (production code) |
| 3 (Medium) | Shared across teams |
| 2 (Low) | M2 Pro ops agents (tests, docs, infra) |
| 1 (Nice-to-have) | Background tasks |

---

## Agent Runtime

### agent-launcher.sh

Core runtime script that all agents use:

```
agent-launcher.sh <role> <repo-path> [poll-interval]
    │
    ├── Poll: curl Vikunja API → find tasks with matching role label
    │
    ├── Claim: curl Vikunja API → set percent_done=0.5
    │
    ├── Execute: codex --quiet --approval-mode full-auto
    │   └── Prompt includes: agent-instructions/<role>.md
    │   └── Runs in target repo directory
    │
    ├── Push: git push -u origin agent/<role>/task-<id>
    │
    ├── PR: gh pr create with task details
    │
    └── Done: curl Vikunja API → mark task done with PR URL
```

### LaunchAgent Persistence

Each agent runs as a macOS LaunchAgent (`~/Library/LaunchAgents/`):
- Starts on login, restarts on failure
- Logs to `~/logs/agent-<role>.log`
- Polls every 120s (tech-writer: 180s)
- Vikunja accessed via SSH tunnel (port forward to axinova-internal.xyz)

### Role Instructions

Each role has a dedicated instruction file in `agent-instructions/`:
- `backend-sde.md` — Go conventions, sqlc, chi v5, test requirements
- `frontend-sde.md` — Vue 3 Composition API, PrimeVue, Tailwind
- `devops.md` — Docker Compose, Traefik, health checks, monitoring
- `qa-testing.md` — Test coverage, security scanning, govulncheck
- `tech-writer.md` — SilverBullet wiki, API docs, runbooks

---

## Communication Channels

| Channel | Purpose | Used By |
|---------|---------|---------|
| **Discord** (via OpenClaw) | Task creation, status queries, PR notifications | Wei → OpenClaw → agents |
| **Vikunja** | Task tracking, assignment, comments, audit trail | All agents |
| **GitHub** | PRs, code review, CI/CD | Backend SDE, Frontend SDE, DevOps, QA |
| **SilverBullet Wiki** | Documentation, runbooks, agent activity logs | Tech Writer, all agents |

---

## Human-in-the-Loop

Wei reviews and merges all PRs. The workflow:

```
Agent creates PR → Wei reviews on phone → Merge → GitHub Actions CI → Deploy
```

With the M1 workstation (10.66.66.4), Wei can also:
- Access Claude Code remotely from phone during work hours (10am-6pm)
- Plan tasks and assign to agents
- Do hands-on coding via Claude Code sessions
- Review PRs and manage the fleet

---

## Scaling Roadmap

### Phase 1 (Current): Manual Coordination
- Human assigns tasks via Discord or Vikunja
- Agents run CI locally, create PRs
- Human reviews and merges all PRs

### Phase 2: Automated Coordination
- Coordinator agents auto-assign tasks based on priority and capacity
- Agents collaborate via Vikunja comments
- Auto-merge for docs/tests (with CI checks passing)

### Phase 3: Multi-Agent Workflows
- Agents create sub-tasks for each other
- Backend → Frontend handoffs (API → UI)
- QA auto-generates test tasks when new PRs merge

### Future Agent Roles

As the fleet evolves, potential additions:
- **Security Engineer** — Pen testing, security audits, dependency scanning
- **Data Engineer** — ETL pipelines, analytics
- **Mobile Engineer** — React Native or Flutter apps
- **AI Researcher** — LLM fine-tuning, evaluation (leveraging M2 Pro's Ollama)

The architecture supports arbitrary agent roles — define responsibilities, create `agent-instructions/<role>.md`, add a launchd plist, and the agent-launcher handles the rest.
