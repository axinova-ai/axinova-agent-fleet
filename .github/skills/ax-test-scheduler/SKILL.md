---
name: ax-test-scheduler
description: Run the agent scheduler e2e test suite. Verifies model routing, founder guard, race prevention, and complexity escalation. Use after making changes to agent-launcher.sh.
---

# Agent Scheduler E2E Test

Run the scheduler e2e test to verify all scheduling scenarios work correctly.

## Step 1: Run the test script

Execute the test script from the axinova-agent-fleet repo:

```bash
cd ~/workspace/axinova-agent-fleet && ./scripts/tests/scheduler-e2e.sh --timeout 240
```

This creates 7 mock tasks in Vikunja, waits for agents to process them, and verifies:
- **T1**: Priority 4 → auto-escalate to Needs Founder (priority-based routing)
- **T2**: MODEL: codex → Codex CLI routing
- **T3**: MODEL: founder → agents skip (negative test, takes ~4 min)
- **T4**: No MODEL → default Codex CLI
- **T5**: Race condition → only 1 agent claims
- **T6**: Complexity → auto-escalation to Needs Founder (keyword scoring)
- **T7**: Blocked dependency → agents skip until resolved

Total runtime: ~7-8 minutes (T3 dominates since it waits to verify nothing happens).

## Step 2: Report results

Show the user the pass/fail table from the output. If any test failed, investigate by checking agent logs:

```bash
ssh agent01 'grep -h "SCHED-TEST" ~/logs/agent-builder-*.log | tail -20'
ssh agent02 'grep -h "SCHED-TEST" ~/logs/agent-builder-*.log | tail -20'
```

## Step 3: Cleanup (if needed)

If the test was interrupted, clean up leftover tasks:

```bash
cd ~/workspace/axinova-agent-fleet && ./scripts/tests/scheduler-e2e.sh --cleanup
```