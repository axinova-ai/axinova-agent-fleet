#!/usr/bin/env bash
set -euo pipefail

# Agent Launcher - Polls Vikunja for tasks and executes via Codex CLI
# Usage: agent-launcher.sh <role> <repo-path> [poll-interval-seconds]
#
# Roles: backend-sde, frontend-sde, devops, qa, tech-writer
# Example: agent-launcher.sh backend-sde ~/workspace/axinova-home-go 120
#
# LLM Strategy (native CLIs, no abstraction):
#   - Codex CLI (OpenAI) → primary coding agent
#   - Kimi K2.5 (via OpenClaw) → task routing
#   - Ollama Qwen (local) → simple tasks (future)

ROLE="${1:?Usage: agent-launcher.sh <role> <repo-path> [poll-interval]}"
REPO_PATH="${2:?Usage: agent-launcher.sh <role> <repo-path> [poll-interval]}"
POLL_INTERVAL="${3:-120}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(dirname "$SCRIPT_DIR")"
INSTRUCTIONS_DIR="$FLEET_DIR/agent-instructions"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/agent-${ROLE}.log"
MCP_BIN="$HOME/workspace/axinova-mcp-server-go/bin/axinova-mcp-server"

mkdir -p "$LOG_DIR"

# Load Discord webhook URLs
DISCORD_WEBHOOKS_ENV="$HOME/.config/axinova/discord-webhooks.env"
# shellcheck disable=SC1090
[[ -f "$DISCORD_WEBHOOKS_ENV" ]] && source "$DISCORD_WEBHOOKS_ENV"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ROLE] $*" | tee -a "$LOG_FILE"
}

notify_discord() {
  local webhook_url="$1"
  local title="$2"
  local description="$3"
  local color="${4:-5814783}"  # Default: blue (0x58ACFF)
  [[ -z "$webhook_url" ]] && return 0
  curl -sf -H "Content-Type: application/json" \
    -d "{\"embeds\":[{\"title\":\"$title\",\"description\":\"$description\",\"color\":$color,\"footer\":{\"text\":\"$ROLE | $(hostname -s)\"}}]}" \
    "$webhook_url" >/dev/null 2>&1 || true
}

# Vikunja API helper (direct HTTP, no LLM needed for task management)
VIKUNJA_URL="${APP_VIKUNJA__URL:-https://vikunja.axinova-internal.xyz}"
VIKUNJA_TOKEN="${APP_VIKUNJA__TOKEN:-}"

vikunja_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local args=(-sf -H "Authorization: Bearer $VIKUNJA_TOKEN" -H "Content-Type: application/json")
  if [[ -n "$data" ]]; then
    args+=(-X "$method" -d "$data")
  elif [[ "$method" != "GET" ]]; then
    args+=(-X "$method")
  fi
  curl "${args[@]}" "${VIKUNJA_URL}/api/v1${endpoint}" 2>/dev/null
}

# Validate role instruction file exists
if [[ ! -f "$INSTRUCTIONS_DIR/${ROLE}.md" ]]; then
  log "ERROR: No instruction file found at $INSTRUCTIONS_DIR/${ROLE}.md"
  exit 1
fi

# Validate repo path
if [[ ! -d "$REPO_PATH" ]]; then
  log "ERROR: Repo path does not exist: $REPO_PATH"
  exit 1
fi

REPO_NAME=$(basename "$REPO_PATH")

log "Starting agent: role=$ROLE repo=$REPO_NAME poll=${POLL_INTERVAL}s"

poll_for_task() {
  # Find the Agent Fleet project and get tasks with matching label
  local projects tasks project_id

  projects=$(vikunja_api GET "/projects" 2>/dev/null) || { echo '{"id": 0}'; return; }
  project_id=$(echo "$projects" | jq -r '.[] | select(.title == "Agent Fleet") | .id // empty' 2>/dev/null)

  if [[ -z "$project_id" ]]; then
    echo '{"id": 0}'
    return
  fi

  tasks=$(vikunja_api GET "/projects/${project_id}/tasks?filter=done=false" 2>/dev/null) || { echo '{"id": 0}'; return; }

  # Find first task with matching role label that isn't claimed
  local task
  task=$(echo "$tasks" | jq -r --arg role "$ROLE" '
    [.[] | select(.labels != null and (.labels[].title == $role)) | select(.percent_done == 0)] | first // {"id": 0}
  ' 2>/dev/null) || { echo '{"id": 0}'; return; }

  echo "$task"
}

claim_task() {
  local task_id="$1"
  log "Claiming task #$task_id"
  vikunja_api POST "/tasks/${task_id}" \
    "{\"percent_done\": 0.5}" >>"$LOG_FILE" 2>&1 || true
}

execute_task() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"
  local branch_name="agent/${ROLE}/task-${task_id}"

  log "Executing task #$task_id: $task_title"

  # Create and switch to branch
  cd "$REPO_PATH"
  git fetch origin main 2>>"$LOG_FILE" || true
  git checkout -b "$branch_name" origin/main 2>>"$LOG_FILE" || {
    git checkout "$branch_name" 2>>"$LOG_FILE" || true
  }

  # Build the prompt
  local role_instructions
  role_instructions=$(cat "$INSTRUCTIONS_DIR/${ROLE}.md")

  local prompt="You are a $ROLE agent working on the $REPO_NAME repository.

## Task #$task_id: $task_title

$task_description

## Instructions
$role_instructions

## Workflow
1. Implement the changes described in the task
2. Run tests to verify your changes work (make test for Go, npm run build for Vue)
3. Stage and commit your changes with a descriptive commit message
4. Do NOT push or create PRs - that will be handled separately

## Important
- Follow the existing code conventions in this repository
- Read CLAUDE.md in the repo root for project-specific guidance
- Keep changes focused on the task - don't refactor unrelated code
- If tests fail, fix them before committing"

  # Execute via Codex CLI (OpenAI native)
  local codex_output
  codex_output=$(codex --quiet \
    --approval-mode full-auto \
    --model codex-mini \
    "$prompt" \
    2>&1) || true

  echo "$codex_output" >> "$LOG_FILE"

  # Check if there are commits to push
  local has_commits
  has_commits=$(git log "origin/main..$branch_name" --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$has_commits" -gt 0 ]]; then
    log "Task #$task_id: $has_commits commit(s) made, pushing and creating PR"

    # Push branch
    git push -u origin "$branch_name" 2>>"$LOG_FILE"

    # Create PR
    local pr_url
    pr_url=$(gh pr create \
      --title "[$ROLE] Task #$task_id: $task_title" \
      --body "$(cat <<PRBODY
## Task
$task_description

## Agent
- Role: \`$ROLE\`
- Machine: \`$(hostname -s)\`
- Vikunja Task: #$task_id

## Changes
$(git log origin/main..$branch_name --pretty=format:'- %s' 2>/dev/null)

---
Automated by Axinova Agent Fleet
PRBODY
)" \
      --base main \
      2>>"$LOG_FILE") || true

    if [[ -n "$pr_url" ]]; then
      log "PR created: $pr_url"
      # Update Vikunja task as done
      vikunja_api POST "/tasks/${task_id}" \
        "{\"done\": true, \"description\": \"PR: ${pr_url}\"}" >>"$LOG_FILE" 2>&1 || true
      # Notify Discord #agent-prs
      notify_discord "${DISCORD_WEBHOOK_PRS:-}" \
        "PR Created — Task #$task_id" \
        "**$task_title**\\n$pr_url\\nRole: \`$ROLE\` | Repo: \`$REPO_NAME\`" \
        5814783  # blue
    else
      log "WARNING: Failed to create PR for task #$task_id"
      notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
        "PR Creation Failed — Task #$task_id" \
        "**$task_title**\\nCommits exist but PR creation failed.\\nRepo: \`$REPO_NAME\` | Branch: \`$branch_name\`" \
        16711680  # red
    fi
  else
    log "Task #$task_id: No commits made, marking as needs-review"
    notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
      "No Changes — Task #$task_id" \
      "**$task_title**\\nAgent completed but made no commits. May need manual review." \
      16776960  # yellow
  fi

  # Switch back to main
  git checkout main 2>>"$LOG_FILE" || true
}

# Main polling loop
while true; do
  log "Polling for tasks..."

  TASK_JSON=$(poll_for_task)

  # Extract task ID
  TASK_ID=$(echo "$TASK_JSON" | jq -r '.id // 0' 2>/dev/null || echo "0")

  if [[ "$TASK_ID" != "0" && "$TASK_ID" != "null" && -n "$TASK_ID" ]]; then
    TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.title // "Untitled"' 2>/dev/null || echo "Untitled")
    TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description // ""' 2>/dev/null || echo "")

    log "Found task #$TASK_ID: $TASK_TITLE"

    claim_task "$TASK_ID"
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Claimed — #$TASK_ID" \
      "**$TASK_TITLE**\\nRole: \`$ROLE\` | Repo: \`$REPO_NAME\`" \
      5814783  # blue

    execute_task "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"

    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Complete — #$TASK_ID" \
      "**$TASK_TITLE**\\nRole: \`$ROLE\` | Repo: \`$REPO_NAME\`" \
      65280  # green

    log "Task #$TASK_ID complete, waiting ${POLL_INTERVAL}s before next poll"
  else
    log "No tasks found, sleeping ${POLL_INTERVAL}s"
  fi

  sleep "$POLL_INTERVAL"
done
