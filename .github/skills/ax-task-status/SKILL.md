---
name: ax-task-status
description: Show current status of all active Vikunja tasks across kanban buckets. Use to get a fleet overview.
---

# Fleet Task Status

Show the current state of all active tasks in Vikunja project 13 (Agent Fleet).

## Step 1: Fetch All Tasks

Use `mcp__axinova-tools__vikunja_list_tasks` with `project_id: 13`.

## Step 2: Display Summary Table

Group tasks by status and show:

| Bucket | # | Tasks |
|--------|---|-------|
| To-Do (pct=0) | count | task titles |
| Doing (pct=0.5) | count | task titles + which agent claimed |
| In Review (pct=0.8) | count | task titles + PR links from comments |
| Needs Founder (pct=0.9) | count | task titles + escalation reason |

Skip Done tasks unless user asks.

## Step 3: Highlight Action Items

Call out:
- Tasks stuck in Doing for >1 hour (agent may have died)
- Tasks in Needs Founder that could be re-routed (suggest `/ax-reroute-task`)
- Tasks in In Review with no PR link (may need manual check)