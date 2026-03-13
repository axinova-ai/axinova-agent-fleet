---
name: ax-create-agent-project
description: Create a new Vikunja project with full kanban setup for agent fleet pickup. Sets up kanban view, all 5 buckets, and sprint labels.
---

# Create Agent-Eligible Vikunja Project

Create a new Vikunja project that agents can auto-discover and pull tasks from.

## Arguments

The user should provide:
- **project name** — must end with `-ag` (e.g., `trader-ag`, `dashboard-ag`)
- **repo name** — the target repo agents will work in (e.g., `axinova-trading-agent-go`)
- **wave labels** (optional) — sprint wave label prefix and count (e.g., `steel-wave 8` creates steel-wave-1 through steel-wave-8)

## Step 1: Create the project

Use `mcp__axinova-tools__vikunja_create_project` with:
- `title`: the project name (MUST end with `-ag`)
- `description`: "Agent-managed project targeting {repo name}"

If the name doesn't end with `-ag`, warn the user that agents won't discover it.

## Step 2: Verify kanban view exists

Use `mcp__axinova-tools__vikunja_list_views` with the new project ID.

Find the kanban view (view_kind == "kanban"). Vikunja auto-creates one with 3 default buckets (To-Do, Doing, Done).

Record the kanban view ID.

## Step 3: Add missing kanban buckets

Use `mcp__axinova-tools__vikunja_list_buckets` to see existing buckets.

Vikunja auto-creates: To-Do, Doing, Done.

Create the missing ones with `mcp__axinova-tools__vikunja_create_bucket`:
- **In Review** — agents move tasks here after creating a PR
- **Needs Founder** — agents escalate tasks they can't complete

All 5 buckets must exist for the agent workflow:
1. To-Do (auto-created)
2. Doing (auto-created)
3. Done (auto-created)
4. In Review (CREATE)
5. Needs Founder (CREATE)

## Step 4: Create wave labels (if requested)

If the user specified wave labels, create them with `mcp__axinova-tools__vikunja_create_label`.

Use distinct colors for each wave:
- Wave 1: `4CAF50` (green)
- Wave 2: `2196F3` (blue)
- Wave 3: `FF9800` (orange)
- Wave 4: `9C27B0` (purple)
- Wave 5: `F44336` (red)
- Wave 6: `607D8B` (blue-gray)
- Wave 7: `795548` (brown)
- Wave 8: `00BCD4` (cyan)
- Wave 9+: `CDDC39` (lime)

## Step 5: Report summary

Show the user:

```
Project created: {name} (ID {id})
Kanban view: {view_id}
Buckets:
  To-Do:         {id}
  Doing:         {id}
  Done:          {id}
  In Review:     {id}
  Needs Founder: {id}
Labels: {list if created}
Target repo: {repo name}

⚠ Agents must be restarted to discover this project.
  Run on M4:     ssh agent01 'for i in $(seq 1 10); do launchctl kickstart -k gui/$(id -u)/com.axinova.agent-builder-$i; done'
  Run on M2 Pro: ssh agent02 'for i in $(seq 11 16); do launchctl kickstart -k gui/$(id -u)/com.axinova.agent-builder-$i; done'

⚠ Task descriptions MUST include the repo name "{repo name}" for agents to detect the target repo.
```

## Important Reminders

- **Project name must end with `-ag`** — agent-launcher.sh filters by this suffix
- **All task descriptions must mention the repo name** — `detect_repo_path()` greps for `axinova-*` patterns
- **Agents only discover projects at startup** — restart agents after creating a new project
- **Wave labels are global** (user-scoped in Vikunja), not per-project — check for existing labels first