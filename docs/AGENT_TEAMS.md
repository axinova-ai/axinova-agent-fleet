# Agent Teams Structure

## Overview

Each Mac mini hosts a **team of specialized agents**, not just a single agent. This allows for role-based task distribution, expertise specialization, and parallel work execution.

## Team Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Mac Mini M4 - Production Team (Agent Team 1)                │
│                                                              │
│ Team Lead: Agent1-Coordinator                                │
│                                                              │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│ │   Backend    │  │   Frontend   │  │   DevOps     │       │
│ │   Engineer   │  │   Engineer   │  │   Engineer   │       │
│ │              │  │              │  │              │       │
│ │ - Go APIs    │  │ - Vue 3      │  │ - Docker     │       │
│ │ - Database   │  │ - TypeScript │  │ - CI/CD      │       │
│ │ - Tests      │  │ - UI/UX      │  │ - Deploy     │       │
│ └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│ ┌──────────────┐  ┌──────────────┐                         │
│ │   Product    │  │   Sales &    │                         │
│ │   Manager    │  │   Marketing  │                         │
│ │              │  │              │                         │
│ │ - Roadmap    │  │ - Campaigns  │                         │
│ │ - Features   │  │ - Content    │                         │
│ │ - Specs      │  │ - Ads        │                         │
│ └──────────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Mac Mini M2 Pro - Research & Learning Team (Agent Team 2)   │
│                                                              │
│ Team Lead: Agent2-Coordinator                                │
│                                                              │
│ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│ │     AI       │  │  Researcher  │  │   Customer   │       │
│ │  Researcher  │  │   & Data     │  │   Support    │       │
│ │              │  │   Analyst    │  │              │       │
│ │ - LLM Train  │  │ - Market     │  │ - Tickets    │       │
│ │ - Fine-tune  │  │ - Tech       │  │ - Docs       │       │
│ │ - Eval       │  │ - Reports    │  │ - FAQ        │       │
│ └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│ ┌──────────────┐  ┌──────────────┐                         │
│ │     QA &     │  │  Technical   │                         │
│ │    Testing   │  │    Writer    │                         │
│ │              │  │              │                         │
│ │ - E2E Tests  │  │ - Runbooks   │                         │
│ │ - Coverage   │  │ - Tutorials  │                         │
│ │ - Security   │  │ - API Docs   │                         │
│ └──────────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

## Agent Roles Detailed

### Team 1 (M4 Mac Mini) - Production Team

#### 1. Backend Engineer Agent

**Responsibilities:**
- Implement Go microservices and APIs
- Design database schemas and migrations
- Write backend tests and benchmarks
- Optimize performance (SQL queries, caching)
- Security (auth, validation, rate limiting)

**Skills:**
- Go programming (standard library, popular frameworks)
- PostgreSQL (schema design, query optimization)
- REST API design
- Unit testing and integration testing
- Docker containerization

**Daily Tasks:**
- Pick Vikunja tasks labeled `backend` or `api`
- Run local CI before committing
- Create PRs with comprehensive test coverage
- Review code from other agents
- Monitor API performance metrics

**Example Work:**
- Implement `/v1/projects` CRUD endpoints
- Add JWT authentication middleware
- Optimize slow database queries
- Write OpenAPI/Swagger specs

---

#### 2. Frontend Engineer Agent

**Responsibilities:**
- Build Vue 3 SPAs with TypeScript
- Implement UI/UX designs from Figma
- Optimize bundle size and performance
- Write frontend tests (unit, component, E2E)
- Accessibility and responsive design

**Skills:**
- Vue 3 (Composition API, Pinia, Vue Router)
- TypeScript (strict mode, generics)
- CSS (Tailwind, responsive design)
- Vite (build optimization, code splitting)
- Vitest/Playwright for testing

**Daily Tasks:**
- Pick Vikunja tasks labeled `frontend` or `ui`
- Implement components and views
- Run type check and build before committing
- Create PRs with screenshots/videos
- Monitor bundle size and lighthouse scores

**Example Work:**
- Build miniapp template gallery component
- Implement dark mode toggle
- Optimize images and lazy-load routes
- Add form validation with Vuelidate

---

#### 3. DevOps Engineer Agent

**Responsibilities:**
- Maintain CI/CD pipelines
- Deploy services to dev/stage/prod
- Monitor infrastructure health
- Manage secrets and configurations
- Automate operational tasks

**Skills:**
- Docker & Docker Compose
- GitHub Actions (workflows, runners)
- Terraform (infrastructure as code)
- Prometheus & Grafana (monitoring)
- Shell scripting (automation)

**Daily Tasks:**
- Pick Vikunja tasks labeled `devops` or `deployment`
- Run deployments via local CI
- Monitor health checks and alerts
- Update infrastructure configs
- Rotate secrets and certificates

**Example Work:**
- Deploy axinova-home-go to prod
- Set up Prometheus alerts for API latency
- Automate database backups
- Update Docker base images for security patches

---

#### 4. Product Manager Agent

**Responsibilities:**
- Define product roadmap and priorities
- Write feature specifications
- Analyze user feedback and metrics
- Coordinate across engineering team
- Track project progress

**Skills:**
- Product strategy and planning
- User research and analytics
- Technical writing (specs, PRDs)
- Stakeholder communication
- Data analysis (SQL, dashboards)

**Daily Tasks:**
- Review Vikunja project boards
- Create new feature tasks with acceptance criteria
- Analyze Grafana dashboards (user metrics)
- Update product roadmap in SilverBullet wiki
- Triage and prioritize GitHub issues

**Example Work:**
- Write PRD for miniapp marketplace feature
- Analyze user engagement data
- Create roadmap for Q2 2026
- Define OKRs and track progress

---

#### 5. Sales & Marketing Agent

**Responsibilities:**
- Create marketing campaigns
- Generate ad copy and creative
- Analyze campaign performance
- Manage social media presence
- Track leads and conversions

**Skills:**
- Copywriting (landing pages, ads)
- Social media marketing
- SEO and content marketing
- Analytics (Google Analytics, Meta Ads)
- Email marketing (campaigns, automation)

**Daily Tasks:**
- Pick Vikunja tasks labeled `marketing` or `sales`
- Create ad campaigns for new features
- Write blog posts and social media content
- Analyze campaign ROI
- Update marketing dashboards

**Example Work:**
- Launch Facebook ad campaign for miniapp builder
- Write blog post: "10 Ways to Build Miniapps Faster"
- Create email drip campaign for trial users
- Optimize landing page conversion rate

---

### Team 2 (M2 Pro Mac Mini) - Research & Learning Team

#### 6. AI Researcher Agent

**Responsibilities:**
- Train domain-specific LLMs from scratch
- Fine-tune models (LoRA, full fine-tuning)
- Evaluate model performance
- Experiment with novel architectures
- Document research findings

**Skills:**
- PyTorch/JAX (model training)
- Transformers architecture
- Tokenization (BPE, character-level)
- Fine-tuning techniques (LoRA, QLoRA)
- Evaluation metrics (perplexity, BLEU, human eval)

**Daily Tasks:**
- Pick Vikunja tasks labeled `ai-research` or `llm`
- Run training experiments on M2 Pro GPU
- Log experiments to SilverBullet wiki
- Evaluate models and compare results
- Share findings with team

**Example Work:**
- Train 2-layer transformer on Axinova docs corpus
- Fine-tune Llama 3 8B on code generation
- Implement character-level tokenizer
- Benchmark model latency and accuracy

**See:** [LLM_LEARNING_JOURNEY.md](LLM_LEARNING_JOURNEY.md) for detailed plan

---

#### 7. Researcher & Data Analyst Agent

**Responsibilities:**
- Market research and competitive analysis
- Technical research (new frameworks, tools)
- Data analysis and visualization
- A/B test design and analysis
- Report generation

**Skills:**
- Data analysis (Python, pandas, SQL)
- Visualization (Matplotlib, Grafana)
- Statistical analysis
- Web scraping and API integration
- Report writing

**Daily Tasks:**
- Pick Vikunja tasks labeled `research` or `analysis`
- Conduct market research
- Analyze user behavior data
- Create dashboards and reports
- Document findings in wiki

**Example Work:**
- Analyze competitor feature sets
- Research Vue 3 performance optimization techniques
- A/B test button color impact on conversions
- Create user retention analysis report

---

#### 8. Customer Support Agent

**Responsibilities:**
- Answer user questions (GitHub issues, email)
- Maintain FAQ and knowledge base
- Triage and escalate bugs
- Improve documentation based on feedback
- Track common issues

**Skills:**
- Technical communication
- Debugging and troubleshooting
- Documentation writing
- Empathy and patience
- Issue tracking (GitHub, Vikunja)

**Daily Tasks:**
- Pick Vikunja tasks labeled `support` or `docs`
- Monitor GitHub issues for questions
- Update FAQ in SilverBullet wiki
- Escalate bugs to engineering team
- Track common pain points

**Example Work:**
- Answer "How do I deploy my miniapp?" issue
- Create tutorial: "Getting Started with Axinova"
- Update troubleshooting guide
- Identify top 10 user pain points

---

#### 9. QA & Testing Agent

**Responsibilities:**
- Write comprehensive test suites
- Perform security testing
- Test coverage analysis
- E2E test automation
- Bug hunting and reporting

**Skills:**
- Test automation (Playwright, Vitest)
- Security testing (OWASP, penetration testing)
- Load testing (k6, Apache Bench)
- Coverage analysis (go test -cover)
- Bug reporting and reproduction

**Daily Tasks:**
- Pick Vikunja tasks labeled `testing` or `qa`
- Write missing tests for low-coverage code
- Run security scans (govulncheck, npm audit)
- Perform exploratory testing
- Report bugs with reproduction steps

**Example Work:**
- Add E2E tests for login flow
- Increase backend test coverage from 70% → 90%
- Perform security audit of auth system
- Load test API endpoints (1000 req/s)

---

#### 10. Technical Writer Agent

**Responsibilities:**
- Write API documentation
- Create runbooks and guides
- Maintain developer documentation
- Write tutorials and examples
- Keep docs up-to-date

**Skills:**
- Technical writing (clear, concise)
- Markdown and documentation tools
- Code examples and snippets
- Diagram creation (Mermaid, PlantUML)
- Version control for docs

**Daily Tasks:**
- Pick Vikunja tasks labeled `documentation` or `tutorial`
- Update API docs for new endpoints
- Write runbooks for common tasks
- Create examples and tutorials
- Review and update stale docs

**Example Work:**
- Write API reference for /v1/projects
- Create runbook: "How to Roll Back a Deployment"
- Tutorial: "Building Your First Miniapp"
- Update architecture diagrams

---

## Team Coordination

### Daily Standup (Automated)

Each team posts a daily summary to SilverBullet wiki:

```markdown
# Daily Standup - 2026-02-08

## Team 1 (Production)
- Backend Engineer: ✅ Completed auth endpoints, 🚧 Working on rate limiting
- Frontend Engineer: ✅ Deployed dark mode, 🚧 Building template gallery
- DevOps Engineer: ✅ Deployed to stage, 🔴 Blocked on SSL cert renewal
- Product Manager: ✅ Wrote PRD for marketplace, 📊 Analyzed user metrics
- Sales & Marketing: ✅ Launched ad campaign, 📈 Generated 50 leads

## Team 2 (Research & Learning)
- AI Researcher: 🚧 Training epoch 7/10, 📊 Perplexity: 3.2 (improving)
- Researcher: ✅ Completed competitor analysis, 📄 Report in wiki
- Customer Support: ✅ Answered 15 issues, 📚 Updated FAQ
- QA & Testing: ✅ Added 20 E2E tests, 📈 Coverage: 85% (+5%)
- Technical Writer: ✅ Wrote deployment runbook, 📝 Updated API docs

## Blockers
- DevOps: Need SSL cert renewed (escalated to human)

## Handoffs
- Backend → QA: New endpoints need testing (#123)
- Frontend → Technical Writer: New UI needs docs (#124)
```

### Task Assignment Rules

**Vikunja Labels (match agent-launcher.sh role names):**
- `backend-sde` → Backend Engineer (M4)
- `frontend-sde` → Frontend Engineer (M4)
- `devops` → DevOps Engineer (M2 Pro)
- `qa-testing` → QA & Testing (M2 Pro)
- `tech-writer` → Technical Writer (M2 Pro)
- `urgent` → All agents (escalation)
- `blocked` → Needs human intervention

**Priority Mapping:**
- Priority 5 (Critical): All agents available for escalation
- Priority 4 (High): Production team (Agent Team 1)
- Priority 3 (Medium): Shared across teams
- Priority 2 (Low): Research team (Agent Team 2)
- Priority 1 (Nice-to-have): Background tasks

### Communication Channels

**GitHub:**
- Pull requests: Engineering team (Backend, Frontend, DevOps)
- Issues: All agents can create and comment
- Discussions: Product, Research, Support agents

**Vikunja:**
- Tasks: Assigned to specific agent role
- Comments: For handoffs and collaboration
- Projects: Organized by team and domain

**SilverBullet Wiki:**
- Runbooks: DevOps, Technical Writer
- Research: AI Researcher, Researcher
- Product Specs: Product Manager
- Meeting Notes: Coordinators

**Discord (via OpenClaw):**
- PM creates tasks via Discord messages
- Agents send PR notifications to #agent-prs
- Status queries via /status command in #agent-tasks
- Deployment triggers via /deploy command
- Alerts and escalations in #agent-alerts

---

## Agent Runtime Implementation

Each agent runs via `scripts/agent-launcher.sh` — a bash script that polls Vikunja via direct HTTP API and executes coding tasks using Codex CLI (OpenAI native).

### Architecture

```
agent-launcher.sh <role> <repo-path> [poll-interval]
    │
    ├── Poll: curl Vikunja API → find tasks with matching role label
    │
    ├── Claim: curl Vikunja API → set percent_done=0.5
    │
    ├── Execute: codex --quiet --approval-mode full-auto --model codex-mini
    │   └── Prompt includes: role instructions from agent-instructions/<role>.md
    │   └── Runs in target repo directory
    │
    ├── Push: git push -u origin agent/<role>/task-<id>
    │
    ├── PR: gh pr create with task details
    │
    └── Done: curl Vikunja API → mark task done with PR URL
```

### Persistence

Each agent runs as a macOS LaunchAgent (in `launchd/`):
- Starts on login, restarts on failure
- Logs to `~/logs/agent-<role>.log`
- Polls every 2 minutes (configurable)

### Role Instructions

Each role has a dedicated instruction file in `agent-instructions/`:
- `backend-sde.md` — Go conventions, sqlc, chi v5, test requirements
- `frontend-sde.md` — Vue 3 Composition API, PrimeVue, Tailwind
- `devops.md` — Docker Compose, Traefik, health checks, monitoring
- `qa-testing.md` — Test coverage, security scanning, govulncheck
- `tech-writer.md` — SilverBullet wiki, API docs, runbooks

### Task Workflow

1. Agent polls Vikunja → finds highest-priority open task with matching label
2. Claims task (sets status to in-progress)
3. Creates branch `agent/<role>/task-<id>`
4. Runs Codex CLI with task description + role instructions
5. Agent implements, runs tests (`make test` / `npm run build`)
6. Commits, pushes, creates PR via `gh pr create`
7. Updates Vikunja task with PR URL, marks as done
8. Logs summary to SilverBullet wiki "Agent Activity Log"

### Starting Agents

```bash
# Manual (for testing)
./scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go 120

# Persistent (via launchd)
cp launchd/com.axinova.agent-backend-sde.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-backend-sde.plist
```

---

## Scaling and Evolution

### Phase 1 (Current): Manual Coordination
- Human assigns tasks to agent roles via Vikunja labels
- Agents run CI locally, create PRs
- Human reviews and merges

### Phase 2 (Month 2-3): Automated Coordination
- Coordinator agents auto-assign tasks
- Agents collaborate via GitHub comments
- Auto-merge for docs/tests (with checks)

### Phase 3 (Month 4-6): Multi-Agent Workflows
- Agents create sub-tasks for each other
- Backend → Frontend handoffs (API → UI)
- Product → Engineering (spec → implementation)
- QA → Engineering (bug report → fix)

### Phase 4 (Month 6+): Autonomous Teams
- Teams plan sprints autonomously
- Self-organize around features
- Report weekly progress to human
- Human only intervenes for strategic decisions

---

## Success Metrics

**Per-Agent Metrics:**
- Tasks completed per week
- PR merge rate (% of PRs merged without changes)
- CI pass rate (% of commits that pass local CI)
- Time to completion (median task duration)

**Team Metrics:**
- Feature delivery velocity (story points per sprint)
- Code quality (test coverage, linter warnings)
- Customer satisfaction (support resolution time)
- Research output (experiments completed, papers written)

**Overall Fleet Metrics:**
- GitHub Actions minutes saved
- Cost per task (OpenAI Codex API usage)
- Human intervention rate (% of tasks needing escalation)
- ROI (value delivered vs. cost)

---

## Future Agent Roles

As the fleet evolves, consider adding:

- **Designer Agent:** Figma mockups, UI/UX design
- **Mobile Engineer Agent:** React Native or Flutter apps
- **Data Engineer Agent:** ETL pipelines, data warehousing
- **Security Engineer Agent:** Pen testing, security audits
- **Business Analyst Agent:** Financial modeling, KPI tracking
- **Content Creator Agent:** Videos, podcasts, graphics
- **Community Manager Agent:** Discord, forums, events

The architecture supports arbitrary agent roles—just define responsibilities, skills, and task labels.
