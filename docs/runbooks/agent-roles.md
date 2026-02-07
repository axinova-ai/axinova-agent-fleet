# Agent Roles and Responsibilities

## Team Structure

### Agent1 (M4 Mac mini) - Delivery Team

**Primary Role:** Feature delivery and production code

**Responsibilities:**
- Create and update feature branches
- Write production code (Go backends, Vue frontends)
- Generate tests and documentation
- Create pull requests for review
- Deploy to dev environment (auto) and stage (with approval)
- Respond to CI failures (fix tests, address linter warnings)

**Target Repositories:**
- axinova-home-go
- axinova-home-web
- axinova-miniapp-builder-go
- axinova-miniapp-builder-web
- axinova-deploy (dev/stage deployments)

**GitHub Identity:**
- Username: `axinova-agent1-bot`
- Email: `agent1@axinova-ai.com`

**Workflow:**
1. Pick task from Vikunja (priority 4-5, label: delivery)
2. Run local CI on Mac mini
3. Push to `agent/feature-*` branch
4. Create PR with description and checklist
5. Wait for human review and approval
6. Deploy to dev (automatic after merge)
7. Update Vikunja task and SilverBullet wiki

**Example Tasks:**
- "Add user authentication to axinova-home"
- "Implement miniapp template gallery"
- "Optimize API response time for /v1/projects"
- "Refactor database layer to use repository pattern"

---

### Agent2 (M2 Pro Mac mini) - Learning & Stability Team

**Primary Role:** Experiments, maintenance, and knowledge work

**Responsibilities:**
- AI/ML experiments (axinova-ai-lab-go)
- Expand test coverage for existing features
- Update documentation (SilverBullet wiki, README files)
- Research and prototype new technologies
- Maintenance tasks (dependency updates, security patches)
- Data analysis and reporting

**Target Repositories:**
- axinova-ai-lab-go
- All repos (for docs/tests only, no prod code changes)
- SilverBullet wiki

**GitHub Identity:**
- Username: `axinova-agent2-bot`
- Email: `agent2@axinova-ai.com`

**Workflow:**
1. Pick task from Vikunja (priority 1-3, label: learning OR maintenance)
2. For AI experiments: Use local Ollama, track results in wiki
3. For docs: Update SilverBullet wiki pages
4. For tests: Add test cases, improve coverage
5. Create PR if code changes needed
6. Self-merge for docs/wiki (no approval needed)
7. Document learnings in wiki

**Example Tasks:**
- "Train character-level transformer on Axinova docs"
- "Add unit tests for authentication middleware"
- "Document deployment process in wiki runbook"
- "Experiment with RAG pipeline for code search"
- "Update Go dependencies to latest patch versions"

---

## Agent Collaboration

### Handoff Scenarios

**Agent1 → Agent2:**
- Feature complete but needs comprehensive tests
- Production bug needs investigation (Agent2 researches, Agent1 fixes)
- New technology research before implementation

**Agent2 → Agent1:**
- Prototype validated, ready for production implementation
- Documentation written, now implement feature
- Security patch researched, Agent1 applies to prod code

### Communication

**Via Vikunja:**
- Agent1 creates tasks with label `delivery`
- Agent2 creates tasks with label `learning`
- Assign tasks to specific agent when needed
- Use task comments for handoff notes

**Via SilverBullet Wiki:**
- Agent1 maintains: `runbooks/`, `architecture/`
- Agent2 maintains: `research/`, `experiments/`
- Both update: `tasks/`, `meetings/` (for standup summaries)

**Via GitHub:**
- Agent1 creates PRs from `agent1/*` branches
- Agent2 creates PRs from `agent2/*` branches
- Use PR comments for clarifications
- Tag each other with `@axinova-agent1-bot` or `@axinova-agent2-bot`

---

## Permission Matrix

| Permission | Agent1 (Delivery) | Agent2 (Learning) | Human |
|------------|-------------------|-------------------|-------|
| Push to `main` | ❌ | ❌ | ✅ |
| Push to `agent/*` branches | ✅ | ✅ | ✅ |
| Create PRs | ✅ | ✅ | ✅ |
| Merge PRs (own) | ❌ | ✅ (docs only) | ✅ |
| Merge PRs (others) | ❌ | ❌ | ✅ |
| Deploy to dev | ✅ | ❌ | ✅ |
| Deploy to stage | ❌ (needs approval) | ❌ | ✅ |
| Deploy to prod | ❌ | ❌ | ✅ |
| Update Vikunja tasks | ✅ | ✅ | ✅ |
| Edit SilverBullet wiki | ✅ | ✅ | ✅ |
| Restart containers (Portainer) | ✅ (dev only) | ❌ | ✅ |

---

## Task Assignment Rules

### Automatic Assignment (via labels)

**Agent1 gets tasks tagged with:**
- `feature`
- `enhancement`
- `refactoring`
- `deployment`
- `delivery`
- Priority 4-5 (high priority)

**Agent2 gets tasks tagged with:**
- `research`
- `experiment`
- `documentation`
- `testing`
- `maintenance`
- `learning`
- Priority 1-3 (lower priority)

### Manual Assignment

**When to assign manually:**
- Task requires specific agent expertise
- Handoff between agents needed
- Time-sensitive production issue (always Agent1)

**How to assign:**
```bash
# Via Vikunja MCP tool
vikunja_update_task(task_id: 123, description: "Assigned to Agent1 for implementation")

# Via GitHub issue
gh issue edit 456 --add-assignee axinova-agent1-bot
```

---

## Quality Standards

### Agent1 (Production Code)

**Code Quality:**
- ✅ All tests pass (go test ./... -race)
- ✅ No linter warnings (go vet, golangci-lint)
- ✅ No vulnerabilities (govulncheck)
- ✅ Code coverage >80% for new code
- ✅ Follows existing patterns in codebase

**PR Requirements:**
- Clear title and description
- Checklist of changes
- Screenshots/logs if applicable
- Links to related issues/tasks

### Agent2 (Experiments & Docs)

**Experiment Quality:**
- ✅ Reproducible from README
- ✅ Results logged in wiki
- ✅ Code commented (explain non-obvious steps)
- ✅ Failure cases documented

**Documentation Quality:**
- ✅ Clear, concise writing
- ✅ Code examples work
- ✅ Up-to-date (no stale references)
- ✅ Links to relevant docs/issues

---

## Daily Workflow

### Agent1 Morning Routine

1. Check Vikunja for new tasks (priority 4-5)
2. Pull latest code from all target repos
3. Run local CI to ensure clean baseline
4. Pick highest-priority task
5. Estimate work (simple/medium/complex)
6. Start work, update task status to "in progress"

### Agent2 Morning Routine

1. Check Vikunja for new tasks (priority 1-3)
2. Review SilverBullet wiki for outdated docs
3. Check test coverage reports for low-coverage files
4. Pick task or create new research task
5. Update wiki page for daily log

### End-of-Day Summary

Both agents create daily summary in SilverBullet wiki:

```markdown
# Daily Log - 2026-02-08

## Agent1 (Delivery)
- ✅ Completed: Task #123 - Add user auth to home-go
- 🚧 In Progress: Task #124 - Implement miniapp templates
- 🔴 Blocked: Waiting for design approval on #125

## Agent2 (Learning)
- ✅ Completed: Updated deployment runbook with rollback steps
- 🚧 In Progress: Training character-level transformer (epoch 5/10)
- 📚 Researched: LoRA fine-tuning techniques (summarized in wiki)

## Handoffs
- Agent1 → Agent2: #123 needs comprehensive tests (assigned)
```

---

## Escalation Path

**If agent gets stuck:**
1. Log issue in Vikunja task comments
2. Create wiki page documenting problem
3. Tag human for help via GitHub issue
4. Pause task, move to next priority item

**When to escalate:**
- Cannot fix failing tests after 3 attempts
- Security vulnerability found (immediate escalation)
- Architecture decision needed (e.g., "use Redis or in-memory cache?")
- Production outage (Agent1 only, immediate escalation)

**How to escalate:**
```bash
# Create GitHub issue
gh issue create \
  --title "🚨 URGENT: Production deployment failing" \
  --body "Agent1 blocked on deployment. Details: ..." \
  --label "urgent" \
  --assignee @me
```

---

## Performance Metrics

Track agent performance weekly in SilverBullet wiki:

**Agent1 Metrics:**
- Tasks completed per week
- Average PR review time (time to merge)
- CI failure rate (% of PRs that fail CI)
- Deployment success rate

**Agent2 Metrics:**
- Experiments completed
- Wiki pages created/updated
- Test coverage improvement (delta)
- Documentation staleness (pages >90 days old)

**Review monthly:**
- Identify bottlenecks (e.g., slow CI, long PR reviews)
- Adjust task assignments (rebalance if one agent overloaded)
- Celebrate wins (e.g., "Agent1 deployed 10 features this month!")
