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

1. Use `mcp__axinova-tools__vikunja_create_task_comment` with:
   `[FOUNDER] PR: <pr-url> | Completed via Codex`
2. Do not rely on `percent_done: 0.8` from Codex unless the live MCP schema is confirmed to support it safely.

This preserves the founder handoff signal even when Codex cannot move the task into In Review itself.

## Step 4: Optionally Self-Merge

If the user explicitly wants an immediate merge:

1. `gh pr merge <number> --squash`
2. Use `mcp__axinova-tools__vikunja_update_task` to set `done: true`
3. Use `mcp__axinova-tools__vikunja_create_task_comment` with: `[DONE] Merged by founder via Codex`

## Notes

- If you use `vikunja_update_task`, preserve the current title/description values when updating to avoid unintended field resets.
- Do not mark the task done before validation and PR creation are complete.
