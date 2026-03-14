# Agent Scheduler E2E Tests

End-to-end tests for `agent-launcher.sh` scheduling logic. Creates real tasks in Vikunja project 13 and verifies that running agents handle them correctly.

## Prerequisites

- Vikunja accessible at `localhost:3456` (SSH tunnel)
- Agents running on agent01 + agent02
- `jq`, `curl` installed
- Token in `~/.config/axinova/{mcp,vikunja,secrets}.env` as `APP_VIKUNJA__TOKEN`

## Usage

```bash
# Run all tests (default 240s timeout)
./scripts/tests/scheduler-e2e.sh

# Custom timeout
./scripts/tests/scheduler-e2e.sh --timeout 300

# Clean up leftover test tasks only
./scripts/tests/scheduler-e2e.sh --cleanup
```

## Test Cases

All tasks are created upfront and polled concurrently. Tests tagged with `[SCHED-TEST]` prefix.

| Test | Scenario | Type | Pass Condition |
|------|----------|------|----------------|
| T1 | Priority 4 auto-escalation | Positive | Task with `priority: 4` gets a `NEEDS FOUNDER` comment (agent detects high priority and escalates) |
| T2 | `MODEL: codex` routing | Positive | Task with `MODEL: codex` in description gets a `codex-exec` comment (agent routes to Codex CLI) |
| T3 | `MODEL: founder` guard | Negative | Task with `MODEL: founder` is **not** claimed by any agent after full timeout window |
| T4 | Default model (no MODEL tag) | Positive | Task without MODEL override gets a `codex-exec` comment (defaults to Codex CLI) |
| T5 | Race condition prevention | Positive | Task gets exactly 1 `CLAIMED` comment despite 16 agents polling concurrently |
| T6 | Complexity auto-escalation | Positive | Task with many complexity keywords in title gets a `NEEDS FOUNDER` comment |
| T7 | Blocked dependency | Two-phase | **Phase 1:** Task blocked by an undone blocker is **not** claimed (verified after half-timeout). **Phase 2:** After marking blocker done, blocked task gets `CLAIMED` |

### Timing

- **Positive tests (T1, T2, T4, T5, T6):** Polled every 10s, pass as soon as the expected comment appears.
- **Negative test (T3):** Must wait the full timeout to confirm no agent claimed it.
- **Two-phase test (T7):** Phase 1 waits half-timeout, then unblocks and polls for phase 2.
- **Typical run:** ~5 min (concurrent). Sequential predecessor took ~13 min.

### How verification works

Each test checks Vikunja task comments via the API:
- `CLAIMED` comment = an agent picked up the task
- `NEEDS FOUNDER` comment = agent escalated to founder bucket
- `codex-exec` comment = agent executed via Codex CLI
- Claim count = number of `CLAIMED` comments (T5 expects exactly 1)

Tasks are automatically closed and cleaned up after the test run.
