---
name: pickup-task
description: Claim a Vikunja task from Needs Founder and start working on it. Use when you want to manually handle a complex task.
argument-hint: "[task-id]"
---

# Pickup Task $ARGUMENTS

You are picking up Vikunja task **#$ARGUMENTS** for manual founder work. Follow this exact sequence:

## Step 1: Read Task Context

1. Use `mcp__axinova-tools__vikunja_get_task` to fetch task #$ARGUMENTS
2. Use `mcp__axinova-tools__vikunja_get_task_comments` to read the audit trail
3. Summarize: task title, why it was escalated (look for `[NEEDS FOUNDER]`, `[BLOCKED]`, or `[TIMEOUT]` comments), which agents attempted it and what failed

## Step 2: Claim the Task

1. Use `mcp__axinova-tools__vikunja_create_task_comment` with comment: `[FOUNDER] Claimed by Codex for manual work`
2. Do not rely on `percent_done` updates from Codex. In this environment, the safe founder claim marker is the task comment plus the active founder branch.

This matches the current launcher fallback: failed Codex builder runs escalate to Needs Founder for direct manual pickup.

## Step 3: Prepare Workspace

1. Extract the repo name from the task title (pattern: `axinova-*-go` or `axinova-*-web`)
2. `cd` into `~/workspace/<repo>`
3. Refresh `main` non-interactively (`git fetch origin`, `git checkout main`, `git pull --ff-only`)
4. Create branch: `git checkout -b founder/task-$ARGUMENTS`
5. Read `AGENTS.md`, `CODEX.md`, `CLAUDE.md`, or `README.md` for project context

## Step 4: Present the Task

Show the user:
- Task title and description
- Escalation reason
- Repo and branch ready

Then proceed with the actual implementation work as directed by the user.

## Notes

- If the repo cannot be determined from the title, stop and ask the user which repo to use.
- If you later use `vikunja_update_task` for description/title changes, preserve the current description explicitly to avoid accidental field wipes from partial-update assumptions.
