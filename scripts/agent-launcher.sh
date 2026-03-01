#!/usr/bin/env bash
set -euo pipefail

# Agent Launcher - Polls Vikunja for tasks and executes via multi-model LLM
# Usage: agent-launcher.sh <role> <repo-path> [poll-interval-seconds]
#
# Roles: backend-sde, frontend-sde, devops, qa-testing, tech-writer
# Example: agent-launcher.sh backend-sde ~/workspace/axinova-home-go 120
#
# LLM Strategy (multi-model with fallback):
#   1. Codex CLI (OpenAI ChatGPT auth) → primary coding agent (has built-in file tools)
#   2. Kimi K2.5 (Moonshot API)        → cloud fallback (unified diff output)
#   3. Ollama (local)                   → simple tasks (docs, lint, format)

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

# --- Secret Loading ---
# Source secrets from env files (NOT hardcoded in plists)
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/moonshot.env" ]] && source "$HOME/.config/axinova/moonshot.env"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/secrets.env" ]] && source "$HOME/.config/axinova/secrets.env"

# Load Discord webhook URLs
DISCORD_WEBHOOKS_ENV="$HOME/.config/axinova/discord-webhooks.env"
# shellcheck disable=SC1090
[[ -f "$DISCORD_WEBHOOKS_ENV" ]] && source "$DISCORD_WEBHOOKS_ENV"

# --- Agent Identity (per-role Discord avatar) ---
get_agent_avatar() {
  case "$1" in
    backend-sde)  echo "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f527.png" ;;
    frontend-sde) echo "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f3a8.png" ;;
    devops)       echo "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/2699.png" ;;
    qa-testing)   echo "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f50d.png" ;;
    tech-writer)  echo "https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f4dd.png" ;;
    *)            echo "" ;;
  esac
}
AGENT_AVATAR=$(get_agent_avatar "$ROLE")
AGENT_USERNAME="Agent: $ROLE"

# --- Logging ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ROLE] $*" | tee -a "$LOG_FILE"
}

# --- Discord Notifications (with per-agent identity) ---
notify_discord() {
  local webhook_url="$1"
  local title="$2"
  local description="$3"
  local color="${4:-5814783}"  # Default: blue (0x58ACFF)
  [[ -z "$webhook_url" ]] && return 0

  local payload
  payload=$(jq -n \
    --arg username "$AGENT_USERNAME" \
    --arg avatar "$AGENT_AVATAR" \
    --arg title "$title" \
    --arg desc "$description" \
    --argjson color "$color" \
    --arg footer "$ROLE | $(hostname -s)" \
    '{
      username: $username,
      avatar_url: $avatar,
      embeds: [{
        title: $title,
        description: $desc,
        color: $color,
        footer: { text: $footer },
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
      }]
    }')

  curl -sf -H "Content-Type: application/json" -d "$payload" "$webhook_url" >/dev/null 2>&1 || true
}

notify_discord_rich() {
  local webhook_url="$1"
  local title="$2"
  local description="$3"
  local color="${4:-5814783}"
  shift 4
  # Remaining args are field pairs: name1 value1 name2 value2 ...
  local fields="[]"
  while [[ $# -ge 2 ]]; do
    fields=$(echo "$fields" | jq --arg n "$1" --arg v "$2" '. + [{"name": $n, "value": $v, "inline": true}]')
    shift 2
  done

  [[ -z "$webhook_url" ]] && return 0

  local payload
  payload=$(jq -n \
    --arg username "$AGENT_USERNAME" \
    --arg avatar "$AGENT_AVATAR" \
    --arg title "$title" \
    --arg desc "$description" \
    --argjson color "$color" \
    --argjson fields "$fields" \
    --arg footer "$ROLE | $(hostname -s)" \
    '{
      username: $username,
      avatar_url: $avatar,
      embeds: [{
        title: $title,
        description: $desc,
        color: $color,
        fields: $fields,
        footer: { text: $footer },
        timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
      }]
    }')

  curl -sf -H "Content-Type: application/json" -d "$payload" "$webhook_url" >/dev/null 2>&1 || true
}

# --- Vikunja API ---
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

# --- Vikunja Task Comments (audit trail) ---
add_task_comment() {
  local task_id="$1"
  local comment="$2"
  local timestamp
  timestamp="[$(date '+%Y-%m-%d %H:%M')]"
  vikunja_api PUT "/tasks/${task_id}/comments" \
    "{\"comment\":\"${timestamp} ${comment}\"}" >/dev/null 2>&1 || true
}

# --- LLM Functions ---

# Kimi K2.5 via Moonshot API (OpenAI-compatible)
call_kimi_api() {
  local prompt="$1"
  local max_tokens="${2:-8192}"

  if [[ -z "${MOONSHOT_API_KEY:-}" ]]; then
    log "ERROR: MOONSHOT_API_KEY not set"
    return 1
  fi

  local response
  response=$(curl -sf --max-time 300 \
    "https://api.moonshot.cn/v1/chat/completions" \
    -H "Authorization: Bearer $MOONSHOT_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg prompt "$prompt" \
      --argjson max_tokens "$max_tokens" \
      '{
        model: "kimi-k2.5",
        messages: [{role: "user", content: $prompt}],
        max_tokens: $max_tokens,
        temperature: 0.2
      }')" 2>&1)

  if [[ $? -ne 0 || -z "$response" ]]; then
    log "ERROR: Kimi API call failed"
    return 1
  fi

  echo "$response" | jq -r '.choices[0].message.content // empty'
}

# Ollama local inference
call_ollama() {
  local prompt="$1"
  local model="${2:-qwen2.5-coder:7b}"
  local ollama_host="${OLLAMA_HOST:-http://localhost:11434}"

  local response
  response=$(curl -sf --max-time 600 \
    "${ollama_host}/api/chat" \
    -d "$(jq -n \
      --arg model "$model" \
      --arg prompt "$prompt" \
      '{
        model: $model,
        messages: [{role: "user", content: $prompt}],
        stream: false
      }')" 2>&1)

  if [[ $? -ne 0 || -z "$response" ]]; then
    log "ERROR: Ollama call failed (model=$model, host=$ollama_host)"
    return 1
  fi

  echo "$response" | jq -r '.message.content // empty'
}

# --- Model Selection ---
select_model() {
  local task_title="$1"

  # Simple heuristic: doc/typo/lint/readme/comment tasks → Ollama (local, zero cost)
  if echo "$task_title" | grep -qiE 'readme|typo|lint|format|comment|doc|todo|changelog|license'; then
    echo "ollama"
    return
  fi

  # Everything else → Kimi K2.5 (cloud, high quality)
  echo "kimi"
}

# Check if Codex CLI is available and working
check_codex_available() {
  command -v codex >/dev/null 2>&1 || return 1
  # Codex is installed — we try it as primary
  return 0
}

# --- Unified Diff Protocol ---
# For text-only LLMs (Kimi, Ollama), we instruct them to output unified diffs
# and apply via `git apply`

build_diff_prompt() {
  local task_title="$1"
  local task_description="$2"
  local role_instructions="$3"
  local repo_name="$4"

  # Gather repo context: file tree (depth 3), recent git log
  local file_tree recent_log
  file_tree=$(find "$REPO_PATH" -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -100 2>/dev/null || true)
  recent_log=$(git -C "$REPO_PATH" log --oneline -5 2>/dev/null || true)

  cat <<PROMPT
You are a $ROLE agent working on the $repo_name repository.

## Task: $task_title

$task_description

## Role Instructions
$role_instructions

## Repository Context
Recent commits:
$recent_log

File tree (partial):
$file_tree

## Output Format

You MUST output ONLY a unified diff that can be applied with \`git apply\`. No commentary, no explanations outside the diff.

Use this exact format:
\`\`\`diff
--- a/path/to/file
+++ b/path/to/file
@@ -line,count +line,count @@
 context line
-removed line
+added line
 context line
\`\`\`

Rules:
- Include enough context lines (3+) for clean application
- Use correct relative paths from repo root
- For new files, use \`--- /dev/null\` and \`+++ b/path/to/new/file\`
- For deleted files, use \`--- a/path/to/file\` and \`+++ /dev/null\`
- Output the diff block ONLY — no markdown fences, no commentary before or after
- If you need to modify multiple files, include all changes in a single diff
PROMPT
}

# Extract diff from LLM output (handles markdown fences)
extract_diff() {
  local output="$1"
  # Try to extract from ```diff ... ``` fences first
  local extracted
  extracted=$(echo "$output" | sed -n '/^```diff$/,/^```$/p' | sed '1d;$d')
  if [[ -n "$extracted" ]]; then
    echo "$extracted"
    return
  fi
  # Try ``` ... ``` fences
  extracted=$(echo "$output" | sed -n '/^```$/,/^```$/p' | sed '1d;$d')
  if [[ -n "$extracted" ]]; then
    echo "$extracted"
    return
  fi
  # Assume raw diff output
  echo "$output"
}

# Apply unified diff to repo
apply_diff() {
  local diff_content="$1"
  local task_id="$2"

  if [[ -z "$diff_content" || "$diff_content" == "null" ]]; then
    log "WARNING: Empty diff output from LLM"
    return 1
  fi

  cd "$REPO_PATH"

  # Write diff to temp file
  local diff_file
  diff_file=$(mktemp /tmp/agent-diff-XXXXXX.patch)
  echo "$diff_content" > "$diff_file"

  # Try to apply
  if git apply --check "$diff_file" 2>>"$LOG_FILE"; then
    git apply --index "$diff_file" 2>>"$LOG_FILE"
    log "Diff applied successfully"
    rm -f "$diff_file"
    return 0
  else
    local error
    error=$(git apply --check "$diff_file" 2>&1 | head -5)
    log "ERROR: git apply failed: $error"
    add_task_comment "$task_id" "[BLOCKED] git apply failed: $error"
    notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
      "Diff Apply Failed - Task #$task_id" \
      "git apply failed. Check logs for details.\n\`\`\`\n${error}\n\`\`\`" \
      16711680  # red
    rm -f "$diff_file"
    return 1
  fi
}

# --- Validate Setup ---
if [[ ! -f "$INSTRUCTIONS_DIR/${ROLE}.md" ]]; then
  log "ERROR: No instruction file found at $INSTRUCTIONS_DIR/${ROLE}.md"
  exit 1
fi

if [[ ! -d "$REPO_PATH" ]]; then
  log "ERROR: Repo path does not exist: $REPO_PATH"
  exit 1
fi

REPO_NAME=$(basename "$REPO_PATH")

log "Starting agent: role=$ROLE repo=$REPO_NAME poll=${POLL_INTERVAL}s"
log "Models available: codex=$(check_codex_available && echo 'yes' || echo 'no') kimi=$([ -n "${MOONSHOT_API_KEY:-}" ] && echo 'yes' || echo 'no') ollama=$(curl -sf "${OLLAMA_HOST:-http://localhost:11434}/api/tags" >/dev/null 2>&1 && echo 'yes' || echo 'no')"

# --- Task Polling ---
poll_for_task() {
  local projects tasks project_id

  projects=$(vikunja_api GET "/projects" 2>/dev/null) || { echo '{"id": 0}'; return; }
  project_id=$(echo "$projects" | jq -r '.[] | select(.title == "Agent Fleet") | .id // empty' 2>/dev/null)

  if [[ -z "$project_id" ]]; then
    echo '{"id": 0}'
    return
  fi

  tasks=$(vikunja_api GET "/projects/${project_id}/tasks?filter=done=false" 2>/dev/null) || { echo '{"id": 0}'; return; }

  # Find first task with matching role label that isn't claimed (percent_done == 0)
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
  add_task_comment "$task_id" "[CLAIMED] Agent $ROLE on $(hostname -s) picking up task"
}

# Update Vikunja task (POST for update)
update_vikunja_task() {
  local task_id="$1"
  local data="$2"
  vikunja_api POST "/tasks/${task_id}" "$data" >>"$LOG_FILE" 2>&1 || true
}

# --- Task Execution (multi-model) ---
execute_task() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"
  local branch_name="agent/${ROLE}/task-${task_id}"
  local model_used="none"
  local start_time
  start_time=$(date +%s)

  log "Executing task #$task_id: $task_title"

  # Create and switch to branch
  cd "$REPO_PATH"
  git fetch origin main 2>>"$LOG_FILE" || true
  git checkout -b "$branch_name" origin/main 2>>"$LOG_FILE" || {
    git checkout "$branch_name" 2>>"$LOG_FILE" || true
  }

  # Build the prompt / instructions
  local role_instructions
  role_instructions=$(cat "$INSTRUCTIONS_DIR/${ROLE}.md")

  # Select model
  local selected_model
  selected_model=$(select_model "$task_title")
  log "Selected model: $selected_model"
  add_task_comment "$task_id" "[STARTED] Model: $selected_model | Repo: $REPO_NAME"

  local execution_success=false

  # --- Try Codex CLI first (has built-in file tools, best for coding) ---
  if check_codex_available; then
    log "Attempting Codex CLI execution..."
    model_used="codex-cli"

    local codex_prompt="You are a $ROLE agent working on the $REPO_NAME repository.

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

    local codex_output
    if codex_output=$(codex exec \
      --full-auto \
      -C "$REPO_PATH" \
      "$codex_prompt" \
      2>&1); then
      echo "$codex_output" >> "$LOG_FILE"
      log "Codex CLI execution completed"

      # Safety net: if Codex modified files but didn't commit, auto-commit
      cd "$REPO_PATH"
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        log "Codex left uncommitted changes, auto-committing..."
        git add -A
        git commit -m "[$ROLE] Task #$task_id: $task_title

Automated by Axinova Agent Fleet (Codex CLI)
Model: codex-cli" 2>>"$LOG_FILE" || true
      fi

      execution_success=true
    else
      echo "$codex_output" >> "$LOG_FILE"
      log "Codex CLI failed, falling back to $selected_model"
      model_used="$selected_model"
    fi
  else
    model_used="$selected_model"
  fi

  # --- Fallback: Kimi K2.5 or Ollama (unified diff protocol) ---
  if [[ "$execution_success" == "false" ]]; then
    local diff_prompt
    diff_prompt=$(build_diff_prompt "$task_title" "$task_description" "$role_instructions" "$REPO_NAME")

    local llm_output=""

    if [[ "$model_used" == "kimi" ]]; then
      log "Calling Kimi K2.5 API..."
      llm_output=$(call_kimi_api "$diff_prompt") || true
    fi

    # If Kimi failed or model is Ollama, try Ollama
    if [[ -z "$llm_output" && "$model_used" == "kimi" ]]; then
      log "Kimi failed, falling back to Ollama"
      model_used="ollama"
    fi

    if [[ "$model_used" == "ollama" || -z "$llm_output" ]]; then
      log "Calling Ollama..."
      model_used="ollama"
      llm_output=$(call_ollama "$diff_prompt") || true
    fi

    if [[ -n "$llm_output" ]]; then
      echo "$llm_output" >> "$LOG_FILE"

      # Extract and apply diff
      local diff_content
      diff_content=$(extract_diff "$llm_output")

      if apply_diff "$diff_content" "$task_id"; then
        # Commit the applied changes
        cd "$REPO_PATH"
        git add -A
        local commit_msg="[$ROLE] Task #$task_id: $task_title

Automated by Axinova Agent Fleet
Model: $model_used"
        git commit -m "$commit_msg" 2>>"$LOG_FILE" && execution_success=true
      fi
    else
      log "ERROR: All LLM backends failed for task #$task_id"
      add_task_comment "$task_id" "[BLOCKED] All LLM backends failed (codex, kimi, ollama)"
    fi
  fi

  # --- Local CI: run tests before creating PR ---
  local ci_passed=true
  if [[ "$execution_success" == "true" ]]; then
    log "Running local CI checks..."
    add_task_comment "$task_id" "[CI] Running local tests..."
    cd "$REPO_PATH"

    local ci_output=""
    if [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
      # Go project
      if ci_output=$(make test 2>&1); then
        log "Local CI: make test PASSED"
      else
        log "Local CI: make test FAILED"
        ci_passed=false
      fi
    elif [[ -f "package.json" ]]; then
      # Node/Vue project
      if ci_output=$(npm run build 2>&1); then
        log "Local CI: npm run build PASSED"
      else
        log "Local CI: npm run build FAILED"
        ci_passed=false
      fi
    fi

    echo "$ci_output" >> "$LOG_FILE"

    if [[ "$ci_passed" == "false" ]]; then
      local ci_error
      ci_error=$(echo "$ci_output" | tail -20 | head -10)
      add_task_comment "$task_id" "[CI-FAILED] Local tests failed. Attempting fix..."
      log "Local CI failed, attempting to fix with LLM..."

      # Try to fix: send error back to LLM
      local fix_prompt="The following test/build errors occurred after my changes. Fix them.

Error output:
$ci_error

Only output a unified diff to fix the errors. No commentary."

      local fix_output=""
      if [[ "$model_used" == "codex-cli" ]] && check_codex_available; then
        fix_output=$(codex exec --full-auto -C "$REPO_PATH" \
          "Fix the following test failures. Do NOT introduce new features, only fix the failing tests.

$ci_error" 2>&1) || true
        # Auto-commit fix if Codex left changes
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
          git add -A
          git commit -m "[$ROLE] Fix CI failures for task #$task_id" 2>>"$LOG_FILE" || true
        fi
      elif [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
        fix_output=$(call_kimi_api "$fix_prompt") || true
        if [[ -n "$fix_output" ]]; then
          local fix_diff
          fix_diff=$(extract_diff "$fix_output")
          if apply_diff "$fix_diff" "$task_id"; then
            git add -A
            git commit -m "[$ROLE] Fix CI failures for task #$task_id" 2>>"$LOG_FILE" || true
          fi
        fi
      fi

      # Re-run CI after fix attempt
      if [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
        make test >>"$LOG_FILE" 2>&1 && ci_passed=true
      elif [[ -f "package.json" ]]; then
        npm run build >>"$LOG_FILE" 2>&1 && ci_passed=true
      fi

      if [[ "$ci_passed" == "true" ]]; then
        log "Local CI: PASSED after fix"
        add_task_comment "$task_id" "[CI] Tests passed after auto-fix"
      else
        log "Local CI: STILL FAILING after fix attempt"
        add_task_comment "$task_id" "[CI-FAILED] Tests still failing after fix attempt"
      fi
    else
      add_task_comment "$task_id" "[CI] Local tests passed"
    fi
  fi

  # --- Post-execution: push, PR, audit ---
  local duration=$(( $(date +%s) - start_time ))
  local duration_str="$(( duration / 60 ))m$(( duration % 60 ))s"

  # Check if there are commits to push
  local has_commits
  has_commits=$(git -C "$REPO_PATH" log "origin/main..$branch_name" --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$has_commits" -gt 0 ]]; then
    log "Task #$task_id: $has_commits commit(s) made, pushing and creating PR"

    local ci_status_note=""
    if [[ "$ci_passed" == "false" ]]; then
      ci_status_note=" ⚠️ Local CI failed — needs manual review"
    fi

    git -C "$REPO_PATH" push -u origin "$branch_name" 2>>"$LOG_FILE"

    local pr_url
    pr_url=$(cd "$REPO_PATH" && gh pr create \
      --title "[$ROLE] Task #$task_id: $task_title" \
      --body "$(cat <<PRBODY
## Task
$task_description

## Agent
- Role: \`$ROLE\`
- Machine: \`$(hostname -s)\`
- Model: \`$model_used\`
- Duration: $duration_str
- Vikunja Task: #$task_id
- Local CI: $([ "$ci_passed" = "true" ] && echo "PASSED" || echo "FAILED")

## Changes
$(git -C "$REPO_PATH" log origin/main..$branch_name --pretty=format:'- %s' 2>/dev/null)

---
Automated by Axinova Agent Fleet${ci_status_note}
PRBODY
)" \
      --base main \
      2>>"$LOG_FILE") || true

    if [[ -n "$pr_url" ]]; then
      log "PR created: $pr_url"
      # Update Vikunja task as done
      update_vikunja_task "$task_id" "{\"done\": true}"
      add_task_comment "$task_id" "[COMPLETED] PR: $pr_url | Model: $model_used | Duration: $duration_str | Commits: $has_commits | CI: $([ "$ci_passed" = "true" ] && echo "PASSED" || echo "FAILED")"

      # Notify Discord #agent-prs with rich embed
      notify_discord_rich "${DISCORD_WEBHOOK_PRS:-}" \
        "PR Created - Task #$task_id" \
        "**$task_title**\n$pr_url" \
        "$([ "$ci_passed" = "true" ] && echo 65280 || echo 16776960)" \
        "Model" "$model_used" \
        "Duration" "$duration_str" \
        "Repo" "$REPO_NAME" \
        "CI" "$([ "$ci_passed" = "true" ] && echo "PASSED" || echo "FAILED")"
    else
      log "WARNING: Failed to create PR for task #$task_id"
      add_task_comment "$task_id" "[BLOCKED] PR creation failed - commits exist on branch $branch_name"
      notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
        "PR Creation Failed - Task #$task_id" \
        "**$task_title**\nCommits exist but PR creation failed.\nRepo: \`$REPO_NAME\` | Branch: \`$branch_name\`" \
        16711680  # red
    fi
  else
    log "Task #$task_id: No commits made, marking as needs-review"
    add_task_comment "$task_id" "[BLOCKED] No changes produced | Model: $model_used | Duration: $duration_str"
    notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
      "No Changes - Task #$task_id" \
      "**$task_title**\nAgent completed but made no commits. May need manual review." \
      16776960  # yellow
  fi

  # Switch back to main
  git -C "$REPO_PATH" checkout main 2>>"$LOG_FILE" || true
}

# --- PR Review Comment Monitor ---
# Check open PRs created by this agent for new review comments
check_pr_comments() {
  cd "$REPO_PATH"

  # List open PRs by this agent (branch pattern: agent/$ROLE/*)
  local prs
  prs=$(gh pr list --state open --head "agent/${ROLE}/" --json number,title,headRefName,url 2>/dev/null) || return 0

  local pr_count
  pr_count=$(echo "$prs" | jq 'length' 2>/dev/null || echo "0")
  [[ "$pr_count" == "0" ]] && return 0

  log "Checking $pr_count open PR(s) for review comments..."

  echo "$prs" | jq -c '.[]' | while IFS= read -r pr; do
    local pr_number pr_title pr_branch pr_url
    pr_number=$(echo "$pr" | jq -r '.number')
    pr_title=$(echo "$pr" | jq -r '.title')
    pr_branch=$(echo "$pr" | jq -r '.headRefName')
    pr_url=$(echo "$pr" | jq -r '.url')

    # Get review comments (excluding bot's own)
    local comments
    comments=$(gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments" \
      --jq '[.[] | select(.user.login != "harryxiaxia" | not) | select(.user.type != "Bot")] | sort_by(.created_at) | last' \
      2>/dev/null) || continue

    [[ -z "$comments" || "$comments" == "null" ]] && continue

    local comment_body comment_id comment_created
    comment_body=$(echo "$comments" | jq -r '.body // empty')
    comment_id=$(echo "$comments" | jq -r '.id // empty')
    comment_created=$(echo "$comments" | jq -r '.created_at // empty')

    [[ -z "$comment_body" ]] && continue

    # Track which comments we've already addressed (via a marker file)
    local marker_file="$LOG_DIR/.pr-comment-${pr_number}-last"
    local last_addressed=""
    [[ -f "$marker_file" ]] && last_addressed=$(cat "$marker_file")

    if [[ "$comment_id" == "$last_addressed" ]]; then
      continue  # Already addressed this comment
    fi

    log "PR #$pr_number has new review comment (id=$comment_id): ${comment_body:0:80}..."

    # Switch to the PR branch and address the comment
    git fetch origin "$pr_branch" 2>>"$LOG_FILE" || continue
    git checkout "$pr_branch" 2>>"$LOG_FILE" || continue

    local review_prompt="You are a $ROLE agent. A reviewer left this comment on your PR:

## PR: $pr_title
## Review Comment:
$comment_body

## File Context:
$(echo "$comments" | jq -r '.path // empty'): line $(echo "$comments" | jq -r '.line // .original_line // "unknown"')
$(echo "$comments" | jq -r '.diff_hunk // empty')

## Instructions
Address the reviewer's feedback. Make the requested changes.
$(cat "$INSTRUCTIONS_DIR/${ROLE}.md")

## Workflow
1. Make the requested changes
2. Run tests to verify
3. Stage and commit with message: 'Address review comment on PR #$pr_number'
4. Do NOT push - that will be handled separately"

    local review_success=false

    # Use Codex CLI if available, else Kimi
    if check_codex_available; then
      log "Addressing review with Codex CLI..."
      local review_output
      if review_output=$(codex exec --full-auto -C "$REPO_PATH" "$review_prompt" 2>&1); then
        echo "$review_output" >> "$LOG_FILE"
        # Auto-commit if needed
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
          git add -A
          git commit -m "[$ROLE] Address review comment on PR #$pr_number

Feedback: ${comment_body:0:100}" 2>>"$LOG_FILE" || true
        fi
        review_success=true
      fi
    elif [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
      log "Addressing review with Kimi K2.5..."
      local review_output
      review_output=$(call_kimi_api "$review_prompt") || true
      if [[ -n "$review_output" ]]; then
        local review_diff
        review_diff=$(extract_diff "$review_output")
        if apply_diff "$review_diff" "0"; then
          git add -A
          git commit -m "[$ROLE] Address review comment on PR #$pr_number

Feedback: ${comment_body:0:100}" 2>>"$LOG_FILE" && review_success=true
        fi
      fi
    fi

    if [[ "$review_success" == "true" ]]; then
      # Run local CI
      local review_ci=true
      if [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
        make test >>"$LOG_FILE" 2>&1 || review_ci=false
      elif [[ -f "package.json" ]]; then
        npm run build >>"$LOG_FILE" 2>&1 || review_ci=false
      fi

      # Push the fix
      git push origin "$pr_branch" 2>>"$LOG_FILE" || true

      # Reply to the review comment
      gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
        -f body="Addressed in $(git rev-parse --short HEAD). Local CI: $([ "$review_ci" = "true" ] && echo "PASSED" || echo "FAILED")" \
        >>"$LOG_FILE" 2>&1 || true

      log "PR #$pr_number: review comment addressed, pushed fix"
      notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
        "Review Addressed - PR #$pr_number" \
        "**$pr_title**\nAddressed reviewer feedback and pushed fix.\n$pr_url" \
        5814783  # blue
    else
      log "PR #$pr_number: failed to address review comment"
      gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
        -f body="I wasn't able to automatically address this feedback. Flagging for manual review." \
        >>"$LOG_FILE" 2>&1 || true
    fi

    # Mark this comment as addressed
    echo "$comment_id" > "$marker_file"

    # Return to main
    git checkout main 2>>"$LOG_FILE" || true
  done
}

# --- Main Polling Loop ---
while true; do
  log "Polling for tasks..."

  TASK_JSON=$(poll_for_task)

  TASK_ID=$(echo "$TASK_JSON" | jq -r '.id // 0' 2>/dev/null || echo "0")

  if [[ "$TASK_ID" != "0" && "$TASK_ID" != "null" && -n "$TASK_ID" ]]; then
    TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.title // "Untitled"' 2>/dev/null || echo "Untitled")
    TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description // ""' 2>/dev/null || echo "")

    log "Found task #$TASK_ID: $TASK_TITLE"

    claim_task "$TASK_ID"
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Claimed - #$TASK_ID" \
      "**$TASK_TITLE**\nRole: \`$ROLE\` | Repo: \`$REPO_NAME\`" \
      5814783  # blue

    execute_task "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"

    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Complete - #$TASK_ID" \
      "**$TASK_TITLE**\nRole: \`$ROLE\` | Repo: \`$REPO_NAME\`" \
      65280  # green

    log "Task #$TASK_ID complete, waiting ${POLL_INTERVAL}s before next poll"
  else
    # No new tasks — check open PRs for review comments
    check_pr_comments

    log "No tasks found, sleeping ${POLL_INTERVAL}s"
  fi

  sleep "$POLL_INTERVAL"
done
