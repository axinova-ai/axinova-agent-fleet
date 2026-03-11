---
name: reroute-task
description: Send a Needs Founder task back to builders with better instructions or a forced model. Use when a task was over-escalated.
argument-hint: "[task-id] [model: codex|kimi|ollama]"
---

# Re-Route Task $ARGUMENTS

You are sending task **#$ARGUMENTS[0]** back to the builder agents with improved instructions.

## Step 1: Read Current Task

1. Use `mcp__axinova-tools__vikunja_get_task` to fetch the task
2. Use `mcp__axinova-tools__vikunja_get_task_comments` to understand what failed
3. Show the user: title, current description, failure reason

## Step 2: Improve Description

Ask the user if they want to:
- **A)** Add a `MODEL: $ARGUMENTS[1]` override (e.g., `MODEL: codex` to force Codex CLI)
- **B)** Rewrite the description with clearer instructions
- **C)** Both

Compose the new description. Prepend the model override line if specified:
```
MODEL: codex
<rest of description>
```

## Step 3: Reset and Re-Queue

1. Use `mcp__axinova-tools__vikunja_update_task` to update the description AND set `percent_done: 0`
2. Use `mcp__axinova-tools__vikunja_create_task_comment` with:
   `[FOUNDER] Re-routed to builders with improved instructions. Model: <model-or-auto>`

The task will be picked up by the next available builder within ~2 minutes (poll interval).

Confirm to user: "Task #$ARGUMENTS[0] re-queued to To-Do. A builder will pick it up shortly."
