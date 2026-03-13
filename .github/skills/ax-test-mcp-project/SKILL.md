---
name: ax-test-mcp-project
description: Run the MCP multi-project e2e test suite. Validates project creation, label management, filtered task listing, kanban views, bucket operations, and sprint transitions. Use after making changes to axinova-mcp-server-go Vikunja tools.
---

# MCP Multi-Project E2E Test

Run the multi-project e2e test to verify all Vikunja MCP project/label/view features work correctly.

## Step 1: Run the test script

Execute the test script from the axinova-agent-fleet repo:

```bash
cd ~/workspace/axinova-agent-fleet && ./scripts/tests/mcp-project-e2e.sh --mcp-only --timeout 60
```

This creates a temporary test project, labels, views, and tasks, then validates:
- **P1**: Create test project
- **P2**: Resolve project by name
- **L1**: Create sprint labels
- **L2**: Resolve label by name
- **T1**: Create task with labels
- **T2**: Bulk create tasks + label
- **T3**: Filter tasks by label
- **T4**: Filter: label + done=false
- **V1**: Create filtered kanban view
- **V2**: List views for project
- **V3**: Create/verify kanban buckets
- **V4**: Move task between buckets
- **B1**: Sprint transition (bulk label swap)
- **A1**: Agent picks up labeled task (requires --include-agent, skipped by default)

Total runtime: ~10-15 seconds (MCP-only mode).

To also test agent scheduler integration (requires agents running):
```bash
cd ~/workspace/axinova-agent-fleet && ./scripts/tests/mcp-project-e2e.sh --timeout 120
```

## Step 2: Report results

Show the user the pass/fail table from the output. If any test failed, check the error messages inline.

## Step 3: Cleanup (if needed)

If the test was interrupted, clean up leftover projects/labels/tasks:

```bash
cd ~/workspace/axinova-agent-fleet && ./scripts/tests/mcp-project-e2e.sh --cleanup
```

## Key Vikunja API Findings (discovered during test development)

- **View filter format**: `{"filter": {"filter": "done = false", "filter_include_nulls": false}}` — nested object, NOT a string
- **Kanban views auto-create 3 buckets** when `bucket_configuration_mode: "manual"`
- **Task filter as query param**: `GET /projects/{id}/tasks?filter=labels+in+5&filter_include_nulls=false`
- **Labels are global** (user-scoped), not per-project
- **Vikunja version**: v1.0.0-rc3