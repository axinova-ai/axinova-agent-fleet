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
3. Summarize: task title, why it was escalated (look for `[NEEDS FOUNDER]` comments), which agents attempted it and what failed

## Step 2: Claim the Task

1. Use `mcp__axinova-tools__vikunja_update_task` to set `percent_done: 0.5` on task #$ARGUMENTS
2. Use `mcp__axinova-tools__vikunja_create_task_comment` with comment: `[FOUNDER] Claimed by Wei via Claude Code for manual work`

This prevents builder agents from picking it up (they only poll tasks with percent_done=0 in the To-Do bucket).

## Step 3: Prepare Workspace

1. Extract the repo name from the task title (pattern: `axinova-*-go` or `axinova-*-web`)
2. `cd` into `~/workspace/<repo>`
3. `git checkout main && git pull`
4. Create branch: `git checkout -b founder/task-$ARGUMENTS`
5. Read CLAUDE.md or README.md for project context

## Step 4: Present the Task

Show the user:
- Task title and description
- Escalation reason
- Repo and branch ready
- Ask: "Ready to start working on this task?"

Then proceed with the actual implementation work as directed by the user.