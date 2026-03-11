---
name: complete-task
description: Finish a task - create PR, update Vikunja status, and move to In Review or Done. Use after you've finished coding on a picked-up task.
argument-hint: "[task-id]"
---

# Complete Task $ARGUMENTS

You are completing Vikunja task **#$ARGUMENTS** after founder work. Follow this sequence:

## Step 1: Verify Work

1. Run `git status` and `git log --oneline origin/main..HEAD` to see what was done
2. Run local tests: `make test` (Go) or `npm run build` (web)
3. If tests fail, fix them before proceeding

## Step 2: Create PR

1. Push the branch: `git push -u origin $(git branch --show-current)`
2. Create PR: `gh pr create --title "[founder] Task #$ARGUMENTS: <task-title>" --base main`
3. Note the PR URL

## Step 3: Update Vikunja

1. Use `mcp__axinova-tools__vikunja_update_task` to set `percent_done: 0.8` on task #$ARGUMENTS
2. Use `mcp__axinova-tools__vikunja_create_task_comment` with:
   `[FOUNDER] PR: <pr-url> | Completed via Claude Code`

## Step 4: Optionally Self-Merge

Ask the user: "PR created. Want to merge it now, or leave for review?"

If merge:
1. `gh pr merge <number> --squash`
2. Use `mcp__axinova-tools__vikunja_update_task` to set `done: true` and `percent_done: 1`
3. Use `mcp__axinova-tools__vikunja_create_task_comment` with: `[DONE] Merged by founder`
