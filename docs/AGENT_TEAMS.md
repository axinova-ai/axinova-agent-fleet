# Agent Fleet Structure

## Three-Tier Architecture

```
Founder (Wei)
    │  High-level intent: "ship feature X", "fix bug Y"
    │  Entry: Claude Code (MCP), Discord, Vikunja UI
    ▼
Orchestrator (OpenClaw + Kimi K2.5)
    │  Decomposes intent into atomic tasks (one PR each)
    │  Labels for categorization, maximizes parallelism
    │  Creates in Vikunja Project 13
    ▼
Builder Pool (16 generic agents: 10 on M4, 6 on M2 Pro)
    │  Poll Vikunja every 120s
    │  Claim any unclaimed task (no specialization)
    │  Detect repo from task title → execute → PR
    ▼
Founder reviews PR → merge → GitHub Actions → deploy
```

### Why generic builders?

- **No routing logic** — any builder can handle any task (backend, frontend, devops, docs)
- **No idle agents** — if there's frontend work but no backend work, all 10 builders work on frontend
- **Simpler scaling** — add more builders, not more roles
- **The task description is the contract** — rich descriptions from the orchestrator tell builders exactly what to do

## Founder

Wei operates as the human decision-maker at the top of the hierarchy.

**Two access paths:**

| Path | Machine | Use case |
|------|---------|----------|
| **Primary** | M1 MacBook Air (10.66.66.18) | Daily coding machine. Claude Code local, full dev env, SSH to fleet. |
| **Mobile** | M1 Workstation (10.66.66.4, planned) | Remote mirror for phone access during day job (10-6). Limited to task creation and PR review. |

**Founder responsibilities:**
- Define high-level goals and priorities
- Review and merge all PRs (branch protection on main)
- Unblock stuck tasks
- Architecture and strategic decisions

## Orchestrator (OpenClaw)

Runs on M4 as a launchd daemon. Receives messages from Discord and decomposes them into Vikunja tasks.

**Key details:**
- LLM: Moonshot/Kimi K2.5 (temperature 0.2)
- System prompt: `openclaw/task-router-prompt.md`
- Config: `openclaw/openclaw.json`
- GFW bypass: SOCKS5 SSH tunnel to Singapore VPN server
- LaunchAgent: `com.axinova.openclaw`

**How it works:**
1. Wei sends Discord message with high-level intent
2. OpenClaw parses intent, determines scope
3. Decomposes into atomic tasks (one PR each)
4. Creates all independent tasks simultaneously in Vikunja
5. Replies with summary of created tasks

**Orchestrator always creates Vikunja tasks.** It never directly commands a builder. The Vikunja queue is the only interface between orchestrator and builders.

**Commands:**
| Command | Purpose |
|---------|---------|
| `/status` | Fleet status — tasks by state |
| `/queue` | Unclaimed tasks only |
| `/health` | Builder health, stuck task detection |
| `/history [N]` | Recent completed tasks |
| `/decompose <goal>` | Break down goal, confirm, create tasks |
| `/wiki <pages> <instructions>` | Create wiki update task |
| `/deploy <service> <env>` | Create urgent deployment task |
| `/models` | Show LLM model chain |

## Builder Pool

16 identical generic agents across two machines. Each is a `scripts/agent-launcher.sh` process managed by launchd.

- **M4 Mac Mini**: builder-1 through builder-10
- **M2 Pro Mac Mini**: builder-11 through builder-16

### How a builder works

```
agent-launcher.sh builder-N ~/workspace 120
    │
    ├── Poll: curl Vikunja API → find unclaimed tasks (percent_done=0)
    │
    ├── Claim: set percent_done=0.5, add [CLAIMED] comment
    │
    ├── Detect repo: scan task title for axinova-* → cd ~/workspace/<repo>
    │
    ├── Execute: multi-model fallback chain
    │   ├─ Codex CLI (primary) — ChatGPT auth, built-in file tools
    │   ├─ Kimi K2.5 (fallback) — Moonshot API, unified diff
    │   └─ Ollama qwen2.5-coder:7b (local) — zero cloud cost
    │   └── Reads agent-instructions/builder.md + repo CLAUDE.md
    │
    ├── Test: make test (Go) / npm run build (Vue)
    │
    ├── Commit + Push: agent/builder-N/task-<id>
    │
    ├── PR: gh pr create with task details
    │
    └── Done: mark task done in Vikunja with PR URL
```

### Audit trail

Builders add structured comments to Vikunja tasks:
```
[2026-03-07 14:30] [CLAIMED] Agent builder-3 on M4 picking up task
[2026-03-07 14:31] [STARTED] Model: codex-cli | Repo: axinova-home-go | Agent: builder-3
[2026-03-07 14:35] [IN REVIEW] PR: https://github.com/... | Duration: 4m
```

### LaunchAgent configuration

- 16 plists: `com.axinova.agent-builder-{1..16}` (1-10 on M4, 11-16 on M2 Pro)
- RunAtLoad + KeepAlive (restart on failure)
- Logs: `~/logs/agent-builder-N.log`
- Poll interval: 120s

## Labels (Categories, NOT Routing)

Labels describe the type of work for reporting and filtering. They do NOT control which builder picks up a task.

| Label | Color | Use for |
|-------|-------|---------|
| `backend` | blue | Go APIs, handlers, sqlc, migrations |
| `frontend` | sky blue | Vue 3, TypeScript, PrimeVue, Tailwind |
| `devops` | teal | Docker Compose, Traefik, CI/CD, deployment |
| `infra` | orange | Database setup, tooling, provisioning |
| `qa` | lime | E2E testing, release sign-off |
| `testing` | amber | Unit tests, integration tests, coverage |
| `tech-writer` | purple | Wiki, runbooks, API docs |
| `docs` | violet | READMEs, architecture docs |
| `urgent` | red | Priority flag — builder picks this first |
| `blocked` | dark red | Needs unblocking before work starts |

**Label combinations:** `backend` + `testing`, `devops` + `infra`, `frontend` + `urgent`, etc.

## Task Decomposition (Orchestrator's Core Job)

### Principles
1. **One task = one PR** — the natural atomic unit
2. **Maximize parallelism** — independent tasks created simultaneously
3. **Include repo name in title** — builders detect repo from `axinova-*` pattern
4. **Rich descriptions** — Context, Acceptance Criteria, Technical Notes, Dependencies
5. **Express dependencies in description** — "depends on task #X, mock the API if not merged yet"

### Example
Founder says: "Ship user profile feature with backend API and frontend page"

Orchestrator creates 4 tasks simultaneously:
- `[axinova-home-go] Add GET /api/v1/user/profile endpoint` — label: `backend`
- `[axinova-home-go] Add PUT /api/v1/user/profile endpoint` — label: `backend`
- `[axinova-home-web] Add user profile page with edit form` — label: `frontend`
- `[axinova-home-go] Add user profile integration tests` — label: `backend`, `testing`

4 builders work in parallel. No waiting.

## Machines

| Machine | VPN IP | Role | What runs |
|---------|--------|------|-----------|
| M4 Mac Mini | 10.66.66.3 | Orchestrator + Builders | OpenClaw, 10 builders (1-10), Local Console Bot |
| M2 Pro Mac Mini | 10.66.66.2 | Builders + LLM Server | 6 builders (11-16), Ollama (Qwen 2.5 Coder 7B) |
| M1 MacBook Air | 10.66.66.18 | Founder primary | Claude Code, dev env, fleet management |
| M1 Workstation | 10.66.66.4 | Founder mirror (planned) | Claude Code tunnel for phone access |
| VPN Server | 8.222.187.10 | Network hub | AmneziaWG, SOCKS5 relay for GFW bypass |

## Key Files

```
agent-instructions/
  builder.md              # Universal builder instructions (all agents use this)
  backend-sde.md          # Legacy (kept for reference)
  frontend-sde.md         # Legacy
  devops.md               # Legacy
  qa-testing.md           # Legacy
  tech-writer.md          # Legacy
scripts/
  agent-launcher.sh       # Core: polls Vikunja, multi-model execution, audit trail
  fleet-status.sh         # Fleet health dashboard
  openclaw-start.sh       # OpenClaw launcher with SOCKS5 GFW bypass
  proxy-bootstrap.cjs     # Node.js SOCKS5 proxy interceptor
openclaw/
  task-router-prompt.md   # Orchestrator system prompt
  openclaw.json           # Multi-agent + multi-provider config
  setup.sh                # Install & configure OpenClaw
launchd/
  com.axinova.agent-builder-{1..16}.plist  # 16 builders (1-10 M4, 11-16 M2 Pro)
  com.axinova.openclaw.plist               # Orchestrator daemon
  com.axinova.local-console-bot.plist      # Discord → Ollama chat
```

## Security

- **Branch protection:** `main` branch requires PR + review — agents cannot merge
- **Secrets:** `~/.config/axinova/*.env` (chmod 600) — NOT in plist files
- **Auth:** Fine-grained GitHub PAT (repo scope only)
- **Agent user:** Dedicated `agent01` user on M4
- **Network:** AmneziaWG VPN + Thunderbolt bridge between minis

## Scaling Roadmap

### Phase 1 (Current): Founder-driven
- Founder creates intent → orchestrator decomposes → builders execute
- Founder reviews and merges all PRs
- 16 builders (10 on M4, 6 on M2 Pro)

### Phase 2: Orchestrator autonomy
- Orchestrator monitors completed work and creates follow-up tasks
- Auto-merge for docs/tests with CI passing
- Orchestrator detects failed PRs and creates fix tasks

### Phase 3: Multi-orchestrator
- Dedicated orchestrators per domain (product, infra, research)
- Orchestrators coordinate via Vikunja
- Founder sets strategy, orchestrators handle execution
