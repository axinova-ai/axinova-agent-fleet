---
name: reroute-task
description: Send a Needs Founder task back to builders with better instructions or a forced model. Use when a task was over-escalated.
argument-hint: "[task-id] [model: codex|ollama|founder]"
---

# Re-Route Task $ARGUMENTS

You are sending task **#$ARGUMENTS[0]** back to the builder agents with improved instructions.

## Step 1: Read Current Task

1. Use `mcp__axinova-tools__vikunja_get_task` to fetch the task
2. Use `mcp__axinova-tools__vikunja_get_task_comments` to understand what failed
3. Show the user: title, current description, failure reason

## Step 2: Improve Description

If helpful:
- Add a `MODEL: $ARGUMENTS[1]` override when the user wants to force a model
- Rewrite the description with clearer instructions
- Do both

Compose the new description. Prepend the model override line if specified:

```text
MODEL: codex
<rest of description>
```

## Step 3: Reset and Re-Queue

1. If you use `mcp__axinova-tools__vikunja_update_task`, include the full preserved description plus your rewritten description content
2. Use `mcp__axinova-tools__vikunja_create_task_comment` with:
   `[FOUNDER] Re-routed to builders with improved instructions. Model: <model-or-auto>`

## Notes

- The current launcher uses Codex CLI as the only automatic code-task model. Kimi is no longer in the normal code fallback path, so prefer `codex` unless the user explicitly wants `ollama` or a manual founder hold.
- Codex cannot reliably move the task back to To-Do via `percent_done` in this environment. If actual re-queueing is required, note that the Vikunja bucket/status reset must be done outside the current Codex MCP write surface.
- `MODEL: founder` is a valid hold/safety directive, but builders will not pick it up.
