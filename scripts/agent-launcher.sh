#!/usr/bin/env bash
set -euo pipefail

# Agent Launcher - Polls Vikunja for tasks and executes via Claude Code
# Usage: agent-launcher.sh <role> <repo-path> [poll-interval-seconds]
#
# Roles: backend-sde, frontend-sde, devops, qa, tech-writer
# Example: agent-launcher.sh backend-sde ~/workspace/axinova-home-go 120

ROLE="${1:?Usage: agent-launcher.sh <role> <repo-path> [poll-interval]}"
REPO_PATH="${2:?Usage: agent-launcher.sh <role> <repo-path> [poll-interval]}"
POLL_INTERVAL="${3:-120}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(dirname "$SCRIPT_DIR")"
INSTRUCTIONS_DIR="$FLEET_DIR/agent-instructions"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/agent-${ROLE}.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ROLE] $*" | tee -a "$LOG_FILE"
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
  # Use Claude to query Vikunja for tasks matching this role's label
  local result
  result=$(claude -p "Use the vikunja_list_tasks tool to find tasks in the 'Agent Fleet' project. \
Filter for tasks that have the label '$ROLE' and are not done (status is open/in-progress). \
Return ONLY a JSON object with fields: id, title, description, priority. \
If no tasks found, return exactly: {\"id\": 0}. \
Do not include any other text." \
    --output-format json \
    --max-turns 3 \
    2>>"$LOG_FILE" || echo '{"id": 0}')

  echo "$result"
}

claim_task() {
  local task_id="$1"
  log "Claiming task #$task_id"
  claude -p "Use vikunja_update_task to update task $task_id: set it to in-progress status. \
Add a comment: 'Claimed by $ROLE agent on $(hostname -s)'" \
    --max-turns 3 \
    >>"$LOG_FILE" 2>&1 || true
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

  # Execute via Claude Code
  local claude_output
  claude_output=$(claude -p "$prompt" \
    --allowedTools "Bash(make *),Bash(go *),Bash(npm *),Bash(git add*),Bash(git commit*),Read,Edit,Write,Glob,Grep,mcp__axinova-tools__*" \
    --max-turns 30 \
    2>&1) || true

  echo "$claude_output" >> "$LOG_FILE"

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
      --body "## Task
$task_description

## Agent
- Role: \`$ROLE\`
- Machine: \`$(hostname -s)\`
- Vikunja Task: #$task_id

## Changes
$(git log origin/main..$branch_name --pretty=format:'- %s' 2>/dev/null)

---
Automated by Axinova Agent Fleet" \
      --base main \
      2>>"$LOG_FILE") || true

    if [[ -n "$pr_url" ]]; then
      log "PR created: $pr_url"
      # Update Vikunja task with PR URL
      update_task_with_pr "$task_id" "$pr_url"
    else
      log "WARNING: Failed to create PR for task #$task_id"
    fi
  else
    log "Task #$task_id: No commits made, marking as needs-review"
  fi

  # Switch back to main
  git checkout main 2>>"$LOG_FILE" || true
}

update_task_with_pr() {
  local task_id="$1"
  local pr_url="$2"

  claude -p "Use vikunja_update_task to update task $task_id: \
Add a comment with the PR URL: '$pr_url'. \
Set the task status to done." \
    --max-turns 3 \
    >>"$LOG_FILE" 2>&1 || true
}

log_to_wiki() {
  local task_id="$1"
  local task_title="$2"
  local status="$3"

  claude -p "Use silverbullet_update_page to append to the 'Agent Activity Log' page. \
Add a new entry: '- $(date '+%Y-%m-%d %H:%M') | $ROLE | Task #$task_id: $task_title | $status | $(hostname -s)'" \
    --max-turns 3 \
    >>"$LOG_FILE" 2>&1 || true
}

# Main polling loop
while true; do
  log "Polling for tasks..."

  TASK_JSON=$(poll_for_task)

  # Extract task ID (simple jq parse)
  TASK_ID=$(echo "$TASK_JSON" | jq -r '.id // 0' 2>/dev/null || echo "0")

  if [[ "$TASK_ID" != "0" && "$TASK_ID" != "null" && -n "$TASK_ID" ]]; then
    TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.title // "Untitled"' 2>/dev/null || echo "Untitled")
    TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description // ""' 2>/dev/null || echo "")

    log "Found task #$TASK_ID: $TASK_TITLE"

    claim_task "$TASK_ID"
    execute_task "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"
    log_to_wiki "$TASK_ID" "$TASK_TITLE" "completed"

    log "Task #$TASK_ID complete, waiting ${POLL_INTERVAL}s before next poll"
  else
    log "No tasks found, sleeping ${POLL_INTERVAL}s"
  fi

  sleep "$POLL_INTERVAL"
done
