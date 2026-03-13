# Lesson Learned: New Vikunja Project Not Picked Up by Agent Fleet

**Date:** 2026-03-12
**Impact:** 35 steel-wave tasks in trader-ag project sat idle — no agent picked them up for ~30 minutes
**Severity:** Medium — no data loss, but wasted time diagnosing three cascading issues

---

## What Happened

Created a new Vikunja project `trader-ag` (project 29) with 35 tasks for the Steel Dashboard MVP. Expected the agent fleet to auto-discover and pick up tasks. Instead, all agents reported "No tasks found" or "no repo name found".

## Root Causes (3 cascading issues)

### 1. Agent discovery runs only at startup

`discover_eligible_projects()` in `agent-launcher.sh` (line 665) runs **once** when the agent process starts. Agents were already running when trader-ag was created, so they never saw it.

**Fix:** Restarted all 16 agents (`launchctl kickstart -k`).

**Prevention:** Consider periodic re-discovery (e.g., every 10 polls) or a signal-based refresh mechanism.

### 2. Missing kanban buckets for agent workflow

Vikunja auto-creates 3 default buckets (To-Do, Doing, Done) for new kanban views. But the agent launcher's `discover_project_config()` also maps "In Review" and "Needs Founder" buckets. While only To-Do and Doing are required (line 656), agents need Needs Founder for escalation and In Review for PR completion.

**Fix:** Manually created "In Review" (bucket 120) and "Needs Founder" (bucket 121) via MCP.

**Prevention:** Any project setup flow must create all 5 kanban buckets.

### 3. No repo reference in task descriptions

`detect_repo_path()` (line 580) greps task title+description for `axinova-*` patterns. The steel tasks had detailed implementation specs but no repo name, so agents found tasks but skipped them with "no repo name found".

**Fix:** Appended `<h3>Repo</h3><p>axinova-trading-agent-go</p>` to all 35 task descriptions via Vikunja API.

**Prevention:** Task creation must always include repo name in the description.

## Checklist: Creating a New Agent-Eligible Project

1. **Project name must end with `-ag`** — `discover_eligible_projects()` filters by `title | test("-ag$")`
2. **Create kanban view** with `bucket_configuration_mode: "manual"` — Vikunja auto-creates To-Do, Doing, Done
3. **Add missing buckets:** "In Review" and "Needs Founder" — agents use these for workflow
4. **Task descriptions must include repo name** — e.g., `axinova-trading-agent-go` anywhere in description
5. **Restart agents** after creating new project — discovery is startup-only
6. **Verify with logs:** `grep "Eligible projects" ~/logs/agent-builder-1.log` should show the new project count

## Timeline

| Time | Event |
|------|-------|
| 19:17 | trader-ag project + 35 tasks created |
| 19:23 | Noticed agents polling but finding "No tasks" |
| 19:28 | Diagnosed: agents only see project 13, discovery is startup-only |
| 19:32 | Created In Review + Needs Founder buckets |
| 19:32 | Restarted all 16 agents → "Eligible projects: 2 total" |
| 19:32 | Agent finds task but skips: "no repo name found" |
| 19:38 | Added repo reference to all 35 task descriptions |
| 19:40 | Builder-1 claims task #239, creates branch, starts coding |
