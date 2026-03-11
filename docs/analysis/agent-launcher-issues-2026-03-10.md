# Agent Launcher & MCP Vikunja — Issues Analysis

**Date:** 2026-03-10
**Updated:** 2026-03-11 (all critical issues resolved)
**Scope:** `scripts/agent-launcher.sh` (~2036 lines) + `axinova-mcp-server-go` Vikunja client

---

## Agent Launcher Issues

### 1. Race Condition on Task Claiming (CRITICAL) — FIXED 2026-03-11

`poll_for_task()` finds the first task with `percent_done == 0`. There is no atomic lock.

**Fix applied:** Two-layer mitigation:
- Random 1-15s jitter delay in `claim_task()` before claiming
- Re-verify `percent_done` is still 0 after jitter (GET task, check value)
- Random task selection in `poll_for_task()` (was always picking first)

Not fully atomic, but sufficient at 16-agent scale. See Option B below for queue-based alternatives.

---

### 2. Description Wipe on Claim (CRITICAL) — FIXED 2026-03-11

`update_vikunja_task()` now does **full GET-then-POST merge**: fetches existing task, merges patch fields via `jq '. + $patch'`, POSTs the complete object back. No more field wiping.

---

### 3. `check_pr_health()` Uses Uninitialized `REPO_PATH` — FIXED 2026-03-11

Added guard: `if [[ -z "${REPO_PATH:-}" ]]; then log "check_pr_health: no REPO_PATH set, skipping"; return; fi`

---

### 4. macOS `grep -oP` Incompatibility — FIXED 2026-03-11

Replaced `grep -oP 'task-\K\d+'` with `sed -n 's/.*task-\([0-9][0-9]*\).*/\1/p' | head -1`.

---

### 5. No Task Timeout / Stuck-Task Detection — OPEN

If an agent dies mid-task, the task stays in "Doing" (`percent_done=0.5`) forever. Nothing cleans it up. No watchdog, no TTL.

**Workaround:** Founder manually resets stuck tasks via MCP (`vikunja_update_task percent_done=0`) and moves to To-Do bucket.

---

### 6. Naive Polling — No Jitter, No Backoff — FIXED 2026-03-11

Added random jitter to claim delay (1-15s). Random task selection distributes work across available tasks. Still no exponential backoff (not needed at current scale).

---

### 7. jq Parse Error on Control Characters — FIXED 2026-03-11

**Not in original analysis.** Vikunja API returns HTML descriptions containing control characters (U+0000-U+001F) that break jq parsing. `vikunja_api()` now pipes all responses through `tr -d '\000-\010\013\014\016-\037'` to strip invalid chars while preserving newlines and tabs.

---

## MCP Server — `vikunja_update_task` Issues

### 8. GET-then-POST Fix Was Never Implemented (CRITICAL) — FIXED 2026-03-11

`UpdateTask()` now does GET-then-POST internally: fetches existing task, merges only provided fields, POSTs the full object back. Uses `DoneSet`/`PrioritySet` sentinel flags to distinguish "not provided" from "set to zero/false".

---

### 9. `Done bool omitempty` — Can't Mark Task as Undone — FIXED 2026-03-11

`UpdateTaskRequest` now uses `DoneSet bool` sentinel. When caller provides `done: false`, the handler sets `DoneSet=true` and the merger sends `done: false` explicitly.

---

## Additional Fixes (2026-03-11)

### 10. Codex CLI PATH Not Found in launchd

launchd services run with minimal PATH. Codex CLI wasn't found even when installed. Fixed: expanded PATH in script header + `check_codex_available()` searches common npm global paths.

### 11. Kimi Unified Diff Prompt Contradictions

Prompt told Kimi to output ONLY a diff block but also asked for explanations. Removed contradictory instructions. Added pre-apply hunk validation (`grep '^@@'`).

### 12. Comment Spam from Concurrent Enrichment

Multiple agents enriching the same task before claiming produced 10+ duplicate `[ENRICHING]` comments. Fixed: enrichment now runs AFTER claim (only the claiming agent enriches).

### 13. Pre-Claim Validity Check

Added `check_task_validity()` — lightweight check (no LLM) that skips tasks with no repo name or wiki tasks without `WIKI_PAGES:` field. Prevents agents from claiming and immediately failing.

---

## What's Working (verified 2026-03-11)

- Vikunja polling works — jq control char fix resolved silent failures
- Codex CLI → git commit → `gh pr create` path verified (Tasks #147, #151 → PRs #38, #39, CI passed)
- Kimi K2.5 fallback triggers correctly when Codex produces 0 changes
- Complexity scoring correctly escalates multi-component tasks (score ≥ 4)
- No racing — single claims per task in latest batch
- No ENRICHING comment spam — enrichment runs post-claim
- Discord webhook notifications fire correctly
- `check_pr_health()` REPO_PATH guard working
- Wiki task path structurally correct (grep -oP fixed)
- GET-then-POST merge working in both bash and Go MCP server

---

## Remaining Open Items

1. **Stuck-task detection** (#5) — no watchdog for dead agents
2. **Kimi diff quality** — still produces corrupt patches sometimes (e.g., "corrupt patch at line 69")
3. **Complexity threshold tuning** — current threshold (4) may be too aggressive, escalating tasks that Codex could handle
4. **Founder manual pickup workflow** — documented in SilverBullet wiki: `Agent Fleet/Runbooks/Founder Task Pickup`

---

## Options Going Forward

### Option A: Fix the launcher in-place — DONE

All 6 items completed. Fleet operational with 16 agents.

### Option B: Replace scheduling with OSS queue (FUTURE)

Still relevant for eliminating the race condition at the root:

| Option | Overhead | At-most-once | Notes |
|--------|----------|--------------|-------|
| **River** (Go, Postgres) | Low | Yes (`SELECT FOR UPDATE SKIP LOCKED`) | Requires Postgres access from agents |
| **pgmq** (Postgres extension) | Low | Yes | Same infra as River |
| **Vikunja assignee field** | Zero | Partial | Use `assignee` to claim atomically |

Not urgent — jitter + re-verify is working at current 16-agent scale.
