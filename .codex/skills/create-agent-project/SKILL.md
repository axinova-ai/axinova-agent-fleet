---
name: create-agent-project
description: Create a new Vikunja project for agent work and report any remaining manual setup required by the current Codex MCP schema.
argument-hint: "[project-name] [repo-name] [wave-prefix optional]"
---

# Create Agent-Eligible Vikunja Project

Create a new Vikunja project that agents can auto-discover and pull tasks from.

## Arguments

The user should provide:
- **project name** — should end with `-ag` (for example `trader-ag`)
- **repo name** — the target repo agents will work in (for example `axinova-trading-agent-go`)
- **wave labels** (optional) — sprint wave label prefix and count if the live MCP schema supports label creation

## Step 1: Create the project

Use `mcp__axinova-tools__vikunja_create_project` with:
- `title`: the project name
- `description`: `Agent-managed project targeting {repo name}`

If the name does not end with `-ag`, warn the user that agents may not discover it correctly.

## Step 2: Verify project creation

Use `mcp__axinova-tools__vikunja_list_projects` and confirm the new project exists.

## Step 3: Check the live Codex MCP surface before assuming deeper setup exists

The Claude version of this workflow expects Vikunja methods for:
- listing views
- listing buckets
- creating buckets
- creating labels

In Codex, do not assume those methods exist. Verify the live tool schema first.

If those methods are unavailable, stop after project creation and report the exact missing follow-up:
- create or confirm a kanban view
- ensure all 5 buckets exist: To-Do, Doing, Done, In Review, Needs Founder
- create any requested wave labels

## Step 4: Report summary

Show the user:

```text
Project created: {name} (ID {id})
Target repo: {repo name}
Codex MCP follow-up: {what was completed vs. what still requires Claude/manual setup}
```

## Important Reminders

- Project names should end with `-ag`
- Task descriptions must mention the repo name so builders can detect the target repo
- Agents discover new projects based on launcher logic and may need a restart or refresh depending on the deployment state
- Do not claim bucket or label setup is complete unless the current Codex MCP tool surface actually exposed and completed those steps
