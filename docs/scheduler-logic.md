# Agent Scheduler Logic

Current scheduling behavior of `scripts/agent-launcher.sh` as of 2026-03-11.

## Polling Loop

Every agent polls Vikunja every `POLL_INTERVAL` (120s default) for tasks in the **To-Do bucket (35)** with `percent_done=0`.

```
poll_for_task() → check_task_validity() → claim_task() → execute_task()
```

## Task Filtering (pre-claim)

`check_task_validity()` runs BEFORE claiming. Rejects tasks that:

| Check | Logic | Result |
|-------|-------|--------|
| `MODEL: founder` | `grep -qiE "MODEL:\s*founder"` on stripped HTML | Skip (return 1) |
| Wiki without pages | `is_wiki_task` true but no `WIKI_PAGES:` | Skip |
| No repo name | Title+desc doesn't match `axinova-*` | Skip |

## Claim Mechanism

`claim_task()` uses jitter + re-check to prevent races:

1. Random delay 1-15s (`RANDOM % 15 + 1`)
2. Re-fetch task from API
3. If `percent_done != 0` → another agent won, skip
4. Set `percent_done=0.5`, move to Doing bucket, add [CLAIMED] comment

## Model Selection

`select_model()` checks task description for `MODEL:` directive:

| Directive | Effect |
|-----------|--------|
| `MODEL: codex` | Force Codex CLI (gpt-5.4) |
| `MODEL: kimi` | Force Kimi CLI (kimi-k2.5) |
| `MODEL: ollama` | Force Ollama (local) |
| `MODEL: founder` | Rejected in check_task_validity (safety net in select_model too) |
| (none) | Default: try Codex first → fallback to Kimi |

## Complexity Gate

`estimate_complexity()` scores task description. If score ≥ 4, auto-escalates to Needs Founder.

Scoring signals:
- +2: wizard, onboarding, migration, refactor, redesign, admin panel
- +2: multi.*(step|page|component|file)
- +1: various scope keywords (API, database, auth, etc.)

## Execution Flow

```
1. Try Codex CLI (unless MODEL: kimi or MODEL: ollama)
   - Timeout: CODEX_TIMEOUT (300s default)
   - Auto-commit if uncommitted changes left
   - If 0 changes → fallback to selected model

2. Try Kimi CLI (if Codex failed/skipped and model=kimi)
   - Timeout: KIMI_TIMEOUT (600s default)
   - Auto-commit if uncommitted changes left
   - If 0 changes → escalate to Needs Founder

3. Try Ollama (only if MODEL: ollama explicitly set)
   - Diff-based approach (not CLI agent)
```

## Post-Commit Validation

After LLM execution, before PR creation:

| Check | Action |
|-------|--------|
| Wrong task ID in commits | Auto-rewrite via `git filter-branch` (up to 10 commits) |
| Scope creep (unrelated files) | Warn but don't block |
| No commits produced | Escalate to Needs Founder |

## Task History Sanitization

Comments loaded from Vikunja (last 15) are sanitized before injection into LLM prompt:
- All `Task #NNN` references are replaced with the current task ID
- Prevents LLM from writing wrong task IDs in commits

## Bucket Mapping

| Bucket | ID | percent_done | Meaning |
|--------|----|--------------|---------|
| To-Do | 35 | 0 | Available for pickup |
| Doing | 36 | 0.5 | Agent working on it |
| Done | 37 | 1.0 | Completed |
| Needs Founder | 38 | 0.9 | Escalated, human review needed |
| In Review | 39 | 0.8 | PR created, awaiting merge |

## E2E Testing

Run `scripts/test-scheduler-e2e.sh` to verify all scheduling scenarios:

```bash
./scripts/test-scheduler-e2e.sh              # Full test suite (~8 min)
./scripts/test-scheduler-e2e.sh --timeout 180 # Faster timeout
./scripts/test-scheduler-e2e.sh --cleanup     # Close leftover test tasks
```

Tests:
- **T1**: MODEL: kimi routing
- **T2**: MODEL: codex routing
- **T3**: MODEL: founder guard (negative test)
- **T4**: Default model selection
- **T5**: Race condition (only 1 agent claims)
- **T6**: Complexity auto-escalation
