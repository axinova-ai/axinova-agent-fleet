#!/usr/bin/env bash
set -euo pipefail

# Agent Launcher - Generic builder agent that polls Vikunja for tasks
# Usage: agent-launcher.sh <agent-id> <workspace-path> [poll-interval-seconds]
#
# All agents are generic builders — they pick up any unclaimed task.
# The task description specifies which repo(s) to work on.
#
# Example: agent-launcher.sh builder-1 ~/workspace 120
#
# LLM Strategy (multi-model with fallback):
#   1. Codex CLI (OpenAI ChatGPT auth) → primary coding agent (has built-in file tools)
#   2. Kimi K2.5 (Moonshot API)        → cloud fallback (unified diff output)
#   3. Ollama qwen2.5-coder:14b (local) → simple tasks + final fallback

AGENT_ID="${1:?Usage: agent-launcher.sh <agent-id> <workspace-path> [poll-interval]}"
WORKSPACE="${2:?Usage: agent-launcher.sh <agent-id> <workspace-path> [poll-interval]}"
POLL_INTERVAL="${3:-120}"

# Backward compat: ROLE is used in prompts, branch names, commit messages
ROLE="builder"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(dirname "$SCRIPT_DIR")"
INSTRUCTIONS_DIR="$FLEET_DIR/agent-instructions"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/agent-${AGENT_ID}.log"
MCP_BIN="$HOME/workspace/axinova-mcp-server-go/bin/axinova-mcp-server"

mkdir -p "$LOG_DIR"

# --- Secret Loading ---
# Source secrets from env files (NOT hardcoded in plists)
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/moonshot.env" ]] && source "$HOME/.config/axinova/moonshot.env"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/secrets.env" ]] && source "$HOME/.config/axinova/secrets.env"
# shellcheck disable=SC1090
[[ -f "$HOME/.config/axinova/vikunja.env" ]] && source "$HOME/.config/axinova/vikunja.env"

# Load Discord webhook URLs
DISCORD_WEBHOOKS_ENV="$HOME/.config/axinova/discord-webhooks.env"
# shellcheck disable=SC1090
[[ -f "$DISCORD_WEBHOOKS_ENV" ]] && source "$DISCORD_WEBHOOKS_ENV"

# --- Agent Identity (Discord avatar) ---
AGENT_AVATAR="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/1f528.png"  # hammer = builder
AGENT_USERNAME="Agent: $AGENT_ID"

# --- Logging ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$AGENT_ID] $*" | tee -a "$LOG_FILE"
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
    --arg footer "$AGENT_ID | $(hostname -s)" \
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
    --arg footer "$AGENT_ID | $(hostname -s)" \
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

# Kanban bucket IDs (project 13, kanban view 52)
BUCKET_TODO=35
BUCKET_DOING=36
BUCKET_IN_REVIEW=39
BUCKET_NEEDS_FOUNDER=38
BUCKET_DONE=37

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

# --- SilverBullet API ---
SILVERBULLET_URL="${APP_SILVERBULLET__URL:-http://localhost:3001}"
SILVERBULLET_TOKEN="${APP_SILVERBULLET__TOKEN:-}"

silverbullet_get_page() {
  local page="$1"
  local encoded="${page// /%20}"
  curl -sfm30 -H "Authorization: Bearer $SILVERBULLET_TOKEN" \
    "${SILVERBULLET_URL}/.fs/${encoded}.md" 2>/dev/null || true
}

silverbullet_put_page() {
  local page="$1" content="$2"
  local encoded="${page// /%20}"
  printf '%s' "$content" | curl -sfm30 -X PUT \
    -H "Authorization: Bearer $SILVERBULLET_TOKEN" \
    -H "Content-Type: text/plain" \
    --data-binary @- \
    "${SILVERBULLET_URL}/.fs/${encoded}.md" 2>/dev/null || return 1
}

# Detect if a task is a wiki/SilverBullet task (vs. a git/code task)
is_wiki_task() {
  local title="$1" desc="$2"
  echo "$title $desc" | grep -qiE 'WIKI_PAGES:|silverbullet wiki|update wiki page|create wiki page'
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
  local model="${2:-qwen2.5-coder:14b}"
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

# Codex CLI model (configurable via env, default: gpt-5.3-codex)
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"

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
  local task_history="${5:-}"

  # Gather repo context: file tree (depth 3), recent git log
  local file_tree recent_log
  file_tree=$(find "$REPO_PATH" -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -100 2>/dev/null || true)
  recent_log=$(git -C "$REPO_PATH" log --oneline -5 2>/dev/null || true)

  local history_block=""
  if [[ -n "$task_history" ]]; then
    history_block="
## Previous Attempts
$task_history
"
  fi

  cat <<PROMPT
You are a builder agent working on the $repo_name repository.

## Task: $task_title

$task_description
$history_block
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
if [[ ! -f "$INSTRUCTIONS_DIR/builder.md" ]]; then
  log "ERROR: No instruction file found at $INSTRUCTIONS_DIR/builder.md"
  exit 1
fi

if [[ ! -d "$WORKSPACE" ]]; then
  log "ERROR: Workspace path does not exist: $WORKSPACE"
  exit 1
fi

# Detect repo from task title/description — looks for axinova-* repo names
# Returns the full path under WORKSPACE, or empty string if not found
detect_repo_path() {
  local text="$1"
  local repo_name
  repo_name=$(echo "$text" | grep -oE 'axinova-[a-zA-Z0-9_-]+' | head -1)
  if [[ -n "$repo_name" && -d "$WORKSPACE/$repo_name" ]]; then
    echo "$WORKSPACE/$repo_name"
  fi
}

log "Starting agent: id=$AGENT_ID workspace=$WORKSPACE poll=${POLL_INTERVAL}s"
log "Models available: codex=$(check_codex_available && echo "yes($CODEX_MODEL)" || echo 'no') kimi=$([ -n "${MOONSHOT_API_KEY:-}" ] && echo 'yes' || echo 'no') ollama=$(curl -sf "${OLLAMA_HOST:-http://localhost:11434}/api/tags" >/dev/null 2>&1 && echo 'yes' || echo 'no')"

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

  # Find first unclaimed task (percent_done == 0, not done)
  # Generic pool model: any builder can pick up any task
  local task
  task=$(echo "$tasks" | jq -r '
    [.[] | select(.percent_done == 0)] | first // {"id": 0}
  ' 2>/dev/null) || { echo '{"id": 0}'; return; }

  echo "$task"
}

claim_task() {
  local task_id="$1"

  # Random delay (0-5s) to reduce stampede when multiple builders poll simultaneously
  local delay=$((RANDOM % 6))
  log "Claim delay ${delay}s for task #$task_id"
  sleep "$delay"

  # Re-check if task is still unclaimed (another builder may have grabbed it)
  local current
  current=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true
  local current_pct
  current_pct=$(echo "$current" | jq -r '.percent_done // 0' 2>/dev/null)
  if [[ "$current_pct" != "0" ]]; then
    log "Task #$task_id already claimed (percent_done=$current_pct) — skipping"
    return 1
  fi

  log "Claiming task #$task_id"
  update_vikunja_task "$task_id" "{\"percent_done\": 0.5}"
  move_to_bucket "$task_id" "$BUCKET_DOING"
  add_task_comment "$task_id" "[CLAIMED] Agent $AGENT_ID on $(hostname -s) picking up task"
  return 0
}

# Update Vikunja task (POST for update)
# IMPORTANT: Vikunja POST replaces ALL fields. We must preserve description/title
# if they are not explicitly included in the update payload.
update_vikunja_task() {
  local task_id="$1"
  local data="$2"

  # If update doesn't include description, fetch and preserve existing one
  if ! echo "$data" | grep -q '"description"'; then
    local existing
    existing=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true
    if [[ -n "$existing" ]]; then
      local existing_desc existing_title
      existing_desc=$(echo "$existing" | jq -r '.description // ""' 2>/dev/null) || true
      existing_title=$(echo "$existing" | jq -r '.title // ""' 2>/dev/null) || true
      # Merge: inject existing description and title into update payload
      if [[ -n "$existing_desc" ]]; then
        local escaped_desc
        escaped_desc=$(echo "$existing_desc" | jq -Rs .)
        data=$(echo "$data" | jq --argjson desc "$escaped_desc" '. + {description: $desc}')
      fi
      if [[ -n "$existing_title" ]] && ! echo "$data" | grep -q '"title"'; then
        data=$(echo "$data" | jq --arg t "$existing_title" '. + {title: $t}')
      fi
    fi
  fi

  vikunja_api POST "/tasks/${task_id}" "$data" >>"$LOG_FILE" 2>&1 || true
}

# Move task to a kanban bucket (uses view-specific bucket endpoint)
move_to_bucket() {
  local task_id="$1"
  local bucket_id="$2"
  vikunja_api POST "/projects/13/views/52/buckets/${bucket_id}/tasks" "{\"task_id\": $task_id}" >>"$LOG_FILE" 2>&1 || true
}

# Check if task description has enough clarity for execution
# Returns 0 if task is actionable, 1 if too vague
# Auto-enrich a vague task description by analyzing the repo
# Uses Codex CLI or Kimi to generate a proper description from the task title + repo context
auto_enrich_description() {
  local task_id="$1"
  local task_title="$2"
  local repo_path="$3"

  log "Task #$task_id: auto-enriching description from repo context"
  add_task_comment "$task_id" "[ENRICHING] Description is vague — analyzing repo to generate a proper task description"

  local repo_name
  repo_name=$(basename "$repo_path")

  # Gather repo context
  local repo_context=""

  # Check for open PRs (useful for deps tasks)
  local open_prs=""
  if echo "$task_title" | grep -qiE 'dependabot|deps|consolidate'; then
    open_prs=$(cd "$repo_path" && gh pr list --state open --limit 20 --json title,url,headRefName 2>/dev/null | jq -r '.[] | "- \(.title) (\(.headRefName))"' 2>/dev/null || true)
  fi

  # Get recent git log
  local recent_commits
  recent_commits=$(git -C "$repo_path" log --oneline -10 2>/dev/null || true)

  # Get file tree (top-level structure)
  local file_tree
  file_tree=$(find "$repo_path" -maxdepth 2 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -50 2>/dev/null | sed "s|$repo_path/||" || true)

  # Check for CLAUDE.md or README
  local project_docs=""
  [[ -f "$repo_path/CLAUDE.md" ]] && project_docs=$(head -50 "$repo_path/CLAUDE.md" 2>/dev/null)
  [[ -z "$project_docs" && -f "$repo_path/README.md" ]] && project_docs=$(head -50 "$repo_path/README.md" 2>/dev/null)

  # Build the enrichment prompt
  local enrich_prompt="You are a task description writer for an AI agent fleet. Given this task title and repo context, write a clear, actionable task description.

## Task Title
$task_title

## Repo: $repo_name

### File Structure (top-level)
$file_tree

### Recent Commits
$recent_commits
"

  if [[ -n "$open_prs" ]]; then
    enrich_prompt+="
### Open PRs
$open_prs
"
  fi

  if [[ -n "$project_docs" ]]; then
    enrich_prompt+="
### Project Docs (first 50 lines)
$project_docs
"
  fi

  enrich_prompt+="
## Output Format
Write a task description with these sections (plain text, no markdown headers):

Context: What this task is about and why it matters.

Acceptance Criteria:
- Criterion 1
- Criterion 2
- ...

Technical Notes: Any specific files, commands, or approaches to use.

Keep it concise (under 300 words). Be specific about what files to change and what the expected outcome is."

  # Try Kimi first (fast, good at analysis), then Ollama
  local enriched=""
  if [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
    enriched=$(call_kimi_api "$enrich_prompt" 2000) || true
  fi

  if [[ -z "$enriched" ]]; then
    enriched=$(call_ollama "$enrich_prompt") || true
  fi

  if [[ -n "$enriched" && ${#enriched} -gt 50 ]]; then
    # Update the task description in Vikunja
    local escaped_desc
    escaped_desc=$(echo "$enriched" | jq -Rs .)
    update_vikunja_task "$task_id" "{\"description\": $escaped_desc}"
    log "Task #$task_id: description auto-enriched (${#enriched} chars)"
    add_task_comment "$task_id" "[ENRICHED] Auto-generated description from repo analysis. Proceeding with execution."
    echo "$enriched"
    return 0
  else
    log "Task #$task_id: auto-enrichment failed"
    return 1
  fi
}

check_task_clarity() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"

  # Wiki tasks need WIKI_PAGES: in description — can't auto-enrich this
  if is_wiki_task "$task_title" "$task_description"; then
    if [[ -z "$task_description" ]] || ! echo "$task_description" | grep -q "WIKI_PAGES:"; then
      log "Task #$task_id: wiki task but no WIKI_PAGES: in description — unclear"
      add_task_comment "$task_id" "[BLOCKED] Wiki task requires WIKI_PAGES: field in description. Resetting to unclaimed."
      update_vikunja_task "$task_id" '{"percent_done": 0}'
      move_to_bucket "$task_id" "$BUCKET_TODO"
      return 1
    fi
  fi

  # Must contain a repo name (axinova-*) in title or description for code tasks
  if ! is_wiki_task "$task_title" "$task_description"; then
    if ! echo "$task_title $task_description" | grep -qE 'axinova-[a-zA-Z0-9_-]+'; then
      log "Task #$task_id: no repo name found — cannot determine where to work"
      add_task_comment "$task_id" "[BLOCKED] No repo name (axinova-*) found in title or description. Resetting to unclaimed."
      update_vikunja_task "$task_id" '{"percent_done": 0}'
      move_to_bucket "$task_id" "$BUCKET_TODO"
      return 1
    fi
  fi

  # Auto-enrich if description is empty or too short
  if [[ -z "$task_description" || ${#task_description} -lt 20 ]]; then
    log "Task #$task_id: description too short (${#task_description} chars) — attempting auto-enrichment"

    # Detect repo for context
    local repo_path
    repo_path=$(detect_repo_path "$task_title")
    if [[ -z "$repo_path" ]]; then
      log "Task #$task_id: can't auto-enrich — no repo found"
      add_task_comment "$task_id" "[BLOCKED] Task description is empty and no repo found for auto-enrichment. Resetting to unclaimed."
      update_vikunja_task "$task_id" '{"percent_done": 0}'
      move_to_bucket "$task_id" "$BUCKET_TODO"
      return 1
    fi

    local enriched_desc
    if enriched_desc=$(auto_enrich_description "$task_id" "$task_title" "$repo_path"); then
      # Update the variable so the caller has the new description
      # We use a global to pass back the enriched description
      ENRICHED_TASK_DESC="$enriched_desc"
      return 0
    else
      add_task_comment "$task_id" "[BLOCKED] Task description is empty and auto-enrichment failed. Please add a description manually. Resetting to unclaimed."
      update_vikunja_task "$task_id" '{"percent_done": 0}'
      move_to_bucket "$task_id" "$BUCKET_TODO"
      return 1
    fi
  fi

  return 0
}

# Escalate task to "Needs Founder" bucket + Discord alert
escalate_task_to_founder() {
  local task_id="$1"
  local task_title="$2"
  local reason="$3"
  log "ESCALATING task #$task_id to Needs Founder: $reason"
  update_vikunja_task "$task_id" '{"percent_done": 0.9}'
  move_to_bucket "$task_id" "$BUCKET_NEEDS_FOUNDER"
  add_task_comment "$task_id" "[NEEDS FOUNDER] $reason"
  notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
    "🚨 Needs Founder - Task #$task_id" \
    "**$task_title**\n\n**Reason:** $reason\n\nAgent has exhausted retries. Please review and move back to To-Do when ready." \
    16711680  # red
}

# --- Wiki Task Execution (tech-writer role) ---
# Used when task description contains WIKI_PAGES: list.
# Flow: read pages → Codex/Kimi improve → PUT back to SilverBullet → Done (no PR unless repo files changed)
execute_wiki_task() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"
  local start_time
  start_time=$(date +%s)

  # For wiki tasks, detect repo from task or default to agent-fleet
  REPO_PATH=$(detect_repo_path "$task_title $task_description")
  [[ -z "$REPO_PATH" ]] && REPO_PATH="$WORKSPACE/axinova-agent-fleet"
  REPO_NAME=$(basename "$REPO_PATH")
  log "Executing wiki task #$task_id: $task_title (repo: $REPO_NAME)"
  add_task_comment "$task_id" "[STARTED] Wiki task | Model: codex-cli/$CODEX_MODEL (fallback: kimi-k2.5) | Agent: $AGENT_ID"

  # Extract WIKI_PAGES: list from description (comma-separated page names)
  # Strip HTML tags first since Vikunja stores descriptions as HTML
  local plain_desc
  plain_desc=$(echo "$task_description" | sed 's/<[^>]*>//g')
  local wiki_pages_raw=""
  wiki_pages_raw=$(echo "$plain_desc" | sed -n '/WIKI_PAGES:/{ s/.*WIKI_PAGES:[[:space:]]*//; p; }' | head -1 | tr ',' '\n' | sed 's/^ *//; s/ *$//')

  # Build context: read current page contents from SilverBullet
  local pages_context=""
  local page_list=()
  if [[ -n "$wiki_pages_raw" ]]; then
    while IFS= read -r page; do
      [[ -z "$page" ]] && continue
      page_list+=("$page")
      local content
      content=$(silverbullet_get_page "$page")
      pages_context+="=== ${page} ===\n${content}\n\n"
    done <<< "$wiki_pages_raw"
  fi

  local sop_content=""
  [[ -f "$FLEET_DIR/docs/silverbullet-sop.md" ]] && \
    sop_content=$(head -80 "$FLEET_DIR/docs/silverbullet-sop.md")

  local execution_success=false

  # --- Try Codex CLI first (can run curl commands directly) ---
  if check_codex_available && [[ -n "$SILVERBULLET_TOKEN" ]]; then
    log "Attempting Codex CLI for wiki task..."
    local codex_prompt="You are a tech-writer agent. Use curl to read/write SilverBullet wiki pages.

SilverBullet API (use these exact commands):
  Read:  curl -sf -H 'Authorization: Bearer ${SILVERBULLET_TOKEN}' '${SILVERBULLET_URL}/.fs/<page-name>.md'
  Write: printf '%s' '<content>' | curl -sf -X PUT -H 'Authorization: Bearer ${SILVERBULLET_TOKEN}' -H 'Content-Type: text/plain' --data-binary @- '${SILVERBULLET_URL}/.fs/<page-name>.md'
  Note: spaces in page names become %20 in the URL (slashes stay as-is).

Wiki SOP (follow this):
${sop_content}

## Task #${task_id}: ${task_title}
${task_description}

## Current Page Contents
${pages_context}

## Workflow
1. For each page in WIKI_PAGES: improve content following SOP (frontmatter, [[wiki-links]], tables, Related Pages)
2. Write each improved page back via curl PUT
3. If any docs/ files need creating in the repo, create and \`git add\` them
4. \`git commit\` any repo changes (message: '[tech-writer] Task #${task_id}: ${task_title}')
5. Do NOT push"

    if codex exec --full-auto -C "$REPO_PATH" "$codex_prompt" >>"$LOG_FILE" 2>&1; then
      log "Codex wiki task completed"
      execution_success=true
    else
      log "Codex wiki task failed, falling back to Kimi"
    fi
  fi

  # --- Fallback: Kimi K2.5 improves each page individually ---
  if [[ "$execution_success" == "false" && ${#page_list[@]} -gt 0 && -n "${MOONSHOT_API_KEY:-}" ]]; then
    log "Using Kimi K2.5 for wiki pages (${#page_list[@]} pages)..."
    local kimi_success=true
    for page in "${page_list[@]}"; do
      local current_content
      current_content=$(silverbullet_get_page "$page")
      [[ -z "$current_content" ]] && { log "WARNING: Could not read page: $page"; continue; }

      local improve_prompt="You are a tech-writer. Improve this SilverBullet wiki page.

Follow the SOP:
- Add/update frontmatter: title, tags (expanded), owner (platform-engineering), reviewed ($(date +%Y-%m-%d)), status (active), type
- Replace plain text navigation with [[wiki-links]]
- Convert dense paragraphs to tables
- Add Related Pages section at bottom

Task context: ${task_title}
${task_description}

Current content of '${page}':
${current_content}

Return ONLY the complete improved page markdown. No fences, no commentary."

      local improved
      improved=$(call_kimi_api "$improve_prompt" 16000) || { kimi_success=false; continue; }

      if [[ -n "$improved" ]]; then
        if silverbullet_put_page "$page" "$improved"; then
          log "Updated wiki page: $page"
          add_task_comment "$task_id" "[WIKI] Updated: $page"
        else
          log "ERROR: Failed to write wiki page: $page"
          kimi_success=false
        fi
      fi
    done
    [[ "$kimi_success" == "true" ]] && execution_success=true
  fi

  # Handle any git changes (docs/ files created by Codex)
  cd "$REPO_PATH"
  local has_git_changes=false
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    has_git_changes=true
    git add -A
    git commit -m "[tech-writer] Task #${task_id}: ${task_title}

Automated by Axinova Agent Fleet (wiki task)" 2>>"$LOG_FILE" || true
  fi

  local duration=$(( $(date +%s) - start_time ))
  local duration_str="$(( duration / 60 ))m$(( duration % 60 ))s"

  if [[ "$execution_success" == "true" ]]; then
    if [[ "$has_git_changes" == "true" ]]; then
      # Repo changes → push + PR (then review)
      local branch_name="agent/${AGENT_ID}/task-${task_id}"
      git checkout -b "$branch_name" 2>>"$LOG_FILE" || true
      git push -u origin "$branch_name" 2>>"$LOG_FILE" || true
      local pr_url
      pr_url=$(gh pr create \
        --head "$branch_name" \
        --title "[builder] Task #${task_id}: ${task_title}" \
        --body "Wiki + repo update. Vikunja task #${task_id}. Duration: ${duration_str}." \
        --base main 2>>"$LOG_FILE") || true
      local result_msg="[COMPLETED] Wiki + repo changes | Duration: ${duration_str}"
      [[ -n "$pr_url" ]] && result_msg+=" | PR: $pr_url"
      move_to_bucket "$task_id" "$BUCKET_IN_REVIEW"
      add_task_comment "$task_id" "$result_msg"
    else
      # Wiki-only → move straight to Done
      move_to_bucket "$task_id" "$BUCKET_DONE"
      update_vikunja_task "$task_id" '{"done": true}'
      add_task_comment "$task_id" "[COMPLETED] Wiki updated | Duration: ${duration_str} | Pages: ${#page_list[@]}"
    fi
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Wiki Task Done - #${task_id}" \
      "**${task_title}**\nPages updated: ${#page_list[@]} | Duration: ${duration_str}" \
      65280  # green
  else
    escalate_task_to_founder "$task_id" "$task_title" "Wiki task execution failed after codex + kimi attempts"
  fi

  git -C "$REPO_PATH" checkout main 2>>"$LOG_FILE" || true
}

# --- Task Execution (multi-model) ---
execute_task() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"
  local branch_name="agent/${AGENT_ID}/task-${task_id}"
  local model_used="none"
  local start_time
  start_time=$(date +%s)

  log "Executing task #$task_id: $task_title"

  # Route wiki tasks to wiki execution path
  if is_wiki_task "$task_title" "$task_description"; then
    log "Detected wiki task — routing to execute_wiki_task()"
    execute_wiki_task "$task_id" "$task_title" "$task_description"
    return
  fi

  # Detect which repo to work in from the task title/description
  REPO_PATH=$(detect_repo_path "$task_title $task_description")
  if [[ -z "$REPO_PATH" ]]; then
    log "ERROR: Could not detect repo from task title/description"
    escalate_task_to_founder "$task_id" "$task_title" "Could not detect target repo from task. Include a repo name like 'axinova-home-go' in the task title."
    return
  fi
  REPO_NAME=$(basename "$REPO_PATH")
  log "Detected repo: $REPO_NAME"

  # Create and switch to branch
  cd "$REPO_PATH"
  git fetch origin main 2>>"$LOG_FILE" || true
  git checkout -b "$branch_name" origin/main 2>>"$LOG_FILE" || {
    git checkout "$branch_name" 2>>"$LOG_FILE" || true
  }

  # Fetch task comments for context from previous attempts
  local task_history=""
  local comments_json
  comments_json=$(vikunja_api GET "/tasks/$task_id/comments" 2>/dev/null) || true
  if [[ -n "$comments_json" && "$comments_json" != "null" ]]; then
    task_history=$(echo "$comments_json" | jq -r '.[].comment' 2>/dev/null | tail -15)
    if [[ -n "$task_history" ]]; then
      log "Loaded ${#task_history} chars of task history from comments"
    fi
  fi

  # Build the prompt / instructions
  local role_instructions
  role_instructions=$(cat "$INSTRUCTIONS_DIR/builder.md")

  # Select fallback model (only used if Codex CLI fails)
  local selected_model
  selected_model=$(select_model "$task_title")
  log "Fallback model: $selected_model"

  local execution_success=false

  # Build task history section for the prompt
  local history_section=""
  if [[ -n "$task_history" ]]; then
    history_section="
## Previous Attempts (task history)
The following comments show what previous agents tried. Learn from any failures or blocked states:
$task_history
"
  fi

  # --- Try Codex CLI first (has built-in file tools, best for coding) ---
  if check_codex_available; then
    log "Attempting Codex CLI execution (model: $CODEX_MODEL)..."
    model_used="codex-cli/$CODEX_MODEL"
    add_task_comment "$task_id" "[STARTED] Model: codex-cli/$CODEX_MODEL | Repo: $REPO_NAME | Agent: $AGENT_ID"

    local codex_prompt="You are a builder agent working on the $REPO_NAME repository.

## Task #$task_id: $task_title

$task_description
$history_section
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
      --model "$CODEX_MODEL" \
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
        git commit -m "[builder] Task #$task_id: $task_title

Automated by Axinova Agent Fleet ($AGENT_ID, Codex CLI)
Model: codex-cli/$CODEX_MODEL" 2>>"$LOG_FILE" || true
      fi

      execution_success=true
    else
      echo "$codex_output" >> "$LOG_FILE"
      log "Codex CLI failed, falling back to $selected_model"
      model_used="$selected_model"
      add_task_comment "$task_id" "[FALLBACK] Codex CLI failed, switching to $selected_model | Agent: $AGENT_ID"
    fi
  else
    model_used="$selected_model"
    add_task_comment "$task_id" "[STARTED] Model: $selected_model (codex unavailable) | Repo: $REPO_NAME | Agent: $AGENT_ID"
  fi

  # --- Fallback: Kimi K2.5 or Ollama (unified diff protocol) ---
  if [[ "$execution_success" == "false" ]]; then
    local diff_prompt
    diff_prompt=$(build_diff_prompt "$task_title" "$task_description" "$role_instructions" "$REPO_NAME" "$task_history")

    local llm_output=""

    if [[ "$model_used" == "kimi" ]]; then
      log "Calling Kimi K2.5 API..."
      llm_output=$(call_kimi_api "$diff_prompt") || true
    fi

    # If Kimi failed or model is Ollama, try Ollama
    if [[ -z "$llm_output" && "$model_used" == "kimi" ]]; then
      log "Kimi failed, falling back to Ollama"
      model_used="ollama"
      add_task_comment "$task_id" "[FALLBACK] Kimi K2.5 failed, switching to Ollama | Agent: $AGENT_ID"
    fi

    if [[ "$model_used" == "ollama" || -z "$llm_output" ]]; then
      log "Calling Ollama..."
      model_used="ollama"
      # Alert on Discord — local model usage means both cloud models failed
      notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
        "⚠️ **Local model fallback** — Task #$task_id using Ollama (both Codex CLI and Kimi K2.5 unavailable). Agent: $AGENT_ID"
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
        local commit_msg="[builder] Task #$task_id: $task_title

Automated by Axinova Agent Fleet ($AGENT_ID)
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
      --head "$branch_name" \
      --title "[builder] Task #$task_id: $task_title" \
      --body "$(cat <<PRBODY
## Task
$task_description

## Agent
- Builder: \`$AGENT_ID\`
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
      # Move to In Review (not Done — founder reviews the PR first)
      move_to_bucket "$task_id" "$BUCKET_IN_REVIEW"
      # Store PR URL in description so it's visible on Kanban board
      local existing_desc
      existing_desc=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null | jq -r '.description // ""' 2>/dev/null || echo "")
      local pr_note="PR: $pr_url | Model: $model_used | CI: $([ "$ci_passed" = "true" ] && echo "PASSED" || echo "FAILED")"
      local new_desc="${existing_desc:+$existing_desc\n\n}--- Result ---\n$pr_note"
      local escaped_desc
      escaped_desc=$(echo -e "$new_desc" | jq -Rs .)
      update_vikunja_task "$task_id" "{\"percent_done\": 0.8, \"description\": $escaped_desc}"
      add_task_comment "$task_id" "[IN REVIEW] PR: $pr_url | Model: $model_used | Duration: $duration_str | Commits: $has_commits | CI: $([ "$ci_passed" = "true" ] && echo "PASSED" || echo "FAILED")"

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
      escalate_task_to_founder "$task_id" "$task_title" "PR creation failed — commits exist on branch \`$branch_name\` but \`gh pr create\` failed. Repo: $REPO_NAME"
    fi
  else
    log "Task #$task_id: No commits made, escalating to founder"
    escalate_task_to_founder "$task_id" "$task_title" "Agent produced no code changes. Model: $model_used, Duration: $duration_str. May need clearer instructions."
  fi

  # Switch back to main
  git -C "$REPO_PATH" checkout main 2>>"$LOG_FILE" || true
}

# --- PR Retry Thresholds ---
MAX_REVIEW_ATTEMPTS=3      # Max times agent will try to address review comments per PR
MAX_CONFLICT_ATTEMPTS=2    # Max times agent will try to resolve conflicts per PR
MAX_CI_FIX_ATTEMPTS=2      # Max times agent will try to fix CI failures per PR

# Read/increment a counter file, return the new count
increment_counter() {
  local counter_file="$1"
  local count=0
  [[ -f "$counter_file" ]] && count=$(cat "$counter_file" 2>/dev/null || echo "0")
  count=$((count + 1))
  echo "$count" > "$counter_file"
  echo "$count"
}

reset_counter() {
  local counter_file="$1"
  rm -f "$counter_file"
}

# --- Escalate to Discord alerts when agent can't resolve ---
escalate_to_human() {
  local pr_number="$1" pr_title="$2" pr_url="$3" reason="$4"
  log "ESCALATION: PR #$pr_number — $reason"

  # Try to find the Vikunja task ID from the PR branch name (agent/ROLE/task-ID)
  local pr_branch task_id_from_pr
  pr_branch=$(cd "$REPO_PATH" && gh pr view "$pr_number" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")
  task_id_from_pr=$(echo "$pr_branch" | grep -oP 'task-\K\d+' 2>/dev/null || echo "")
  if [[ -n "$task_id_from_pr" ]]; then
    move_to_bucket "$task_id_from_pr" "$BUCKET_NEEDS_FOUNDER"
    add_task_comment "$task_id_from_pr" "[NEEDS FOUNDER] PR #$pr_number: $reason"
  fi

  notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
    "🚨 Needs Founder - PR #$pr_number" \
    "**$pr_title**\n\n**Reason:** $reason\n\nAgent has exhausted automatic retries.\n$pr_url" \
    16711680  # red
  gh pr comment "$pr_number" --body "⚠️ **Agent escalation**: $reason

This PR needs founder attention. Automatic retry limit reached." \
    >>"$LOG_FILE" 2>&1 || true
}

# --- PR Health Monitor ---
# Check for recently merged PRs and auto-close corresponding Vikunja tasks
# Runs across ALL agent PRs, not just this builder's
check_merged_prs() {
  # Get all repos in workspace
  local repos
  repos=$(find "$WORKSPACE" -maxdepth 1 -name "axinova-*" -type d 2>/dev/null)
  [[ -z "$repos" ]] && return 0

  for repo_dir in $repos; do
    local repo_name
    repo_name=$(basename "$repo_dir")
    cd "$repo_dir" 2>/dev/null || continue

    # List recently merged PRs with agent/ branch pattern
    local merged_prs
    merged_prs=$(gh pr list --state merged --limit 20 \
      --json number,title,headRefName,mergedAt \
      2>/dev/null) || continue

    # Filter to agent PRs only
    local agent_prs
    agent_prs=$(echo "$merged_prs" | jq '[.[] | select(.headRefName | startswith("agent/"))]' 2>/dev/null) || continue

    local count
    count=$(echo "$agent_prs" | jq 'length' 2>/dev/null || echo "0")
    [[ "$count" == "0" ]] && continue

    echo "$agent_prs" | jq -c '.[]' | while IFS= read -r pr; do
      local pr_branch pr_title merged_at
      pr_branch=$(echo "$pr" | jq -r '.headRefName')
      pr_title=$(echo "$pr" | jq -r '.title')
      merged_at=$(echo "$pr" | jq -r '.mergedAt')

      # Extract task ID from branch name: agent/builder-N/task-XXX → XXX
      local task_id
      task_id=$(echo "$pr_branch" | grep -oE 'task-[0-9]+' | grep -oE '[0-9]+')
      [[ -z "$task_id" ]] && continue

      # Check if we already processed this merge (avoid duplicate closures)
      local merge_marker="$LOG_DIR/.merged-task-${task_id}"
      [[ -f "$merge_marker" ]] && continue

      # Check if the Vikunja task is still open
      local task_json
      task_json=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null) || continue
      local is_done
      is_done=$(echo "$task_json" | jq -r '.done // false' 2>/dev/null)

      if [[ "$is_done" == "false" ]]; then
        log "PR merged for task #$task_id ($repo_name) — auto-closing Vikunja task"
        update_vikunja_task "$task_id" '{"done": true, "percent_done": 1}'
        add_task_comment "$task_id" "[DONE] PR merged by founder. Closing task automatically."
        move_to_bucket "$task_id" "$BUCKET_DONE"
        notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
          "Task #$task_id auto-closed — PR merged" \
          "**$pr_title**\nRepo: $repo_name\nMerged: $merged_at" \
          65280  # green
        touch "$merge_marker"
      else
        touch "$merge_marker"
      fi
    done
  done
}

# Checks open PRs for: review comments, CI failures, merge conflicts
check_pr_health() {
  # REPO_PATH may not be set if no task has been executed yet this session
  if [[ -z "${REPO_PATH:-}" ]]; then
    log "check_pr_health: no REPO_PATH set, skipping"
    return 0
  fi
  cd "$REPO_PATH"

  # List open PRs by this agent — gh --head requires exact branch, so filter with jq
  local all_prs prs
  all_prs=$(gh pr list --state open \
    --json number,title,headRefName,url,mergeable \
    2>/dev/null) || return 0
  prs=$(echo "$all_prs" | jq --arg aid "$AGENT_ID" \
    '[.[] | select(.headRefName | startswith("agent/"+$aid+"/"))]' 2>/dev/null) || return 0

  local pr_count
  pr_count=$(echo "$prs" | jq 'length' 2>/dev/null || echo "0")
  [[ "$pr_count" == "0" ]] && return 0

  log "Monitoring $pr_count open PR(s)..."

  echo "$prs" | jq -c '.[]' | while IFS= read -r pr; do
    local pr_number pr_title pr_branch pr_url mergeable
    pr_number=$(echo "$pr" | jq -r '.number')
    pr_title=$(echo "$pr" | jq -r '.title')
    pr_branch=$(echo "$pr" | jq -r '.headRefName')
    pr_url=$(echo "$pr" | jq -r '.url')
    mergeable=$(echo "$pr" | jq -r '.mergeable // "UNKNOWN"')

    # --- 1. Check for CI failures via REST commit status (works without checks scope) ---
    local head_sha check_status
    head_sha=$(cd "$REPO_PATH" && gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null || echo "")
    if [[ -n "$head_sha" ]]; then
      # Use combined status + check-runs REST endpoints (no GraphQL needed)
      local combined_status check_runs_conclusion
      combined_status=$(cd "$REPO_PATH" && gh api "repos/{owner}/{repo}/commits/${head_sha}/status" --jq '.state' 2>/dev/null || echo "")
      check_runs_conclusion=$(cd "$REPO_PATH" && gh api "repos/{owner}/{repo}/commits/${head_sha}/check-runs" --jq \
        '[.check_runs[]? | .conclusion] | if length == 0 then "none" elif any(. == "failure") then "failure" elif any(. == null) then "pending" else "success" end' 2>/dev/null || echo "none")
      if [[ "$combined_status" == "failure" || "$check_runs_conclusion" == "failure" ]]; then
        check_status="FAILURE"
      elif [[ "$combined_status" == "pending" || "$check_runs_conclusion" == "pending" ]]; then
        check_status="PENDING"
      elif [[ "$combined_status" == "success" || "$check_runs_conclusion" == "success" ]]; then
        check_status="SUCCESS"
      else
        check_status="NONE"
      fi
    else
      check_status="NONE"
    fi

    if [[ "$check_status" == "FAILURE" ]]; then
      local ci_counter_file="$LOG_DIR/.pr-ci-fix-${pr_number}-count"
      local ci_attempts
      ci_attempts=$(cat "$ci_counter_file" 2>/dev/null || echo "0")

      if [[ "$ci_attempts" -ge "$MAX_CI_FIX_ATTEMPTS" ]]; then
        # Already at limit — check if we've already escalated
        local ci_escalated_file="$LOG_DIR/.pr-ci-fix-${pr_number}-escalated"
        if [[ ! -f "$ci_escalated_file" ]]; then
          escalate_to_human "$pr_number" "$pr_title" "$pr_url" \
            "CI checks failing after $ci_attempts fix attempts"
          touch "$ci_escalated_file"
        fi
      else
        log "PR #$pr_number: CI failing, attempt $((ci_attempts + 1))/$MAX_CI_FIX_ATTEMPTS to fix..."
        _fix_ci_failure "$pr_number" "$pr_title" "$pr_branch" "$pr_url" "$ci_counter_file"
      fi
    fi

    # --- 2. Check for merge conflicts ---
    if [[ "$mergeable" == "CONFLICTING" ]]; then
      local conflict_counter_file="$LOG_DIR/.pr-conflict-${pr_number}-count"
      local conflict_attempts
      conflict_attempts=$(cat "$conflict_counter_file" 2>/dev/null || echo "0")

      if [[ "$conflict_attempts" -ge "$MAX_CONFLICT_ATTEMPTS" ]]; then
        local conflict_escalated_file="$LOG_DIR/.pr-conflict-${pr_number}-escalated"
        if [[ ! -f "$conflict_escalated_file" ]]; then
          escalate_to_human "$pr_number" "$pr_title" "$pr_url" \
            "Merge conflicts persist after $conflict_attempts rebase attempts"
          touch "$conflict_escalated_file"
        fi
      else
        log "PR #$pr_number: conflicts detected, attempt $((conflict_attempts + 1))/$MAX_CONFLICT_ATTEMPTS..."
        _resolve_conflicts "$pr_number" "$pr_title" "$pr_branch" "$pr_url" "$conflict_counter_file"
      fi
    fi

    # --- 3. Check for new review comments ---
    _check_review_comments "$pr_number" "$pr_title" "$pr_branch" "$pr_url"

  done
}

# --- Fix CI Failures ---
_fix_ci_failure() {
  local pr_number="$1" pr_title="$2" pr_branch="$3" pr_url="$4" counter_file="$5"

  git fetch origin "$pr_branch" 2>>"$LOG_FILE" || return
  git checkout "$pr_branch" 2>>"$LOG_FILE" || return

  # Get the failing check names and logs
  local failed_checks
  failed_checks=$(gh pr checks "$pr_number" --json name,conclusion,detailsUrl \
    --jq '[.[] | select(.conclusion == "FAILURE" or .conclusion == "failure")] | .[0:3] | map(.name + ": " + .detailsUrl) | join("\n")' \
    2>/dev/null || echo "unknown")

  local fix_prompt="You are a builder agent. CI checks are failing on your PR.

## PR: $pr_title
## Failing Checks:
$failed_checks

## Instructions
1. Read the failing test/build output carefully
2. Fix the code to make CI pass
3. Run tests locally to verify: make test (Go) or npm run build (Node)
4. Stage and commit with message: '[builder] Fix CI failure on PR #$pr_number'
5. Do NOT push

$(cat "$INSTRUCTIONS_DIR/${ROLE}.md" 2>/dev/null || true)"

  local fix_success=false

  if check_codex_available; then
    log "Fixing CI with Codex CLI..."
    if codex exec --full-auto -C "$REPO_PATH" "$fix_prompt" >>"$LOG_FILE" 2>&1; then
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git add -A
        git commit -m "[$ROLE] Fix CI failure on PR #$pr_number" 2>>"$LOG_FILE" || true
      fi
      fix_success=true
    fi
  elif [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
    log "Fixing CI with Kimi K2.5..."
    local fix_output
    fix_output=$(call_kimi_api "$fix_prompt") || true
    if [[ -n "$fix_output" ]]; then
      local fix_diff
      fix_diff=$(extract_diff "$fix_output")
      if apply_diff "$fix_diff" "0"; then
        git add -A
        git commit -m "[$ROLE] Fix CI failure on PR #$pr_number" 2>>"$LOG_FILE" && fix_success=true
      fi
    fi
  fi

  increment_counter "$counter_file" > /dev/null

  if [[ "$fix_success" == "true" ]]; then
    # Verify locally before pushing
    local ci_ok=true
    if [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
      make test >>"$LOG_FILE" 2>&1 || ci_ok=false
    elif [[ -f "package.json" ]]; then
      npm run build >>"$LOG_FILE" 2>&1 || ci_ok=false
    fi

    git push origin "$pr_branch" 2>>"$LOG_FILE" || true

    gh pr comment "$pr_number" --body "Pushed CI fix ($(git rev-parse --short HEAD)). Local CI: $([ "$ci_ok" = "true" ] && echo "PASSED" || echo "FAILED")" \
      >>"$LOG_FILE" 2>&1 || true

    log "PR #$pr_number: CI fix pushed"
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "CI Fix Pushed - PR #$pr_number" \
      "**$pr_title**\nAttempted CI fix and pushed.\n$pr_url" \
      5814783  # blue
  else
    log "PR #$pr_number: CI fix attempt failed"
  fi

  git checkout main 2>>"$LOG_FILE" || true
}

# --- Resolve Merge Conflicts ---
_resolve_conflicts() {
  local pr_number="$1" pr_title="$2" pr_branch="$3" pr_url="$4" counter_file="$5"

  git fetch origin main "$pr_branch" 2>>"$LOG_FILE" || return
  git checkout "$pr_branch" 2>>"$LOG_FILE" || return

  if git rebase origin/main 2>>"$LOG_FILE"; then
    git push --force-with-lease origin "$pr_branch" 2>>"$LOG_FILE" || {
      log "PR #$pr_number: rebase succeeded but push failed"
      increment_counter "$counter_file" > /dev/null
      git checkout main 2>>"$LOG_FILE" || true
      return
    }
    log "PR #$pr_number: conflicts resolved via rebase"
    reset_counter "$counter_file"
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Conflicts Resolved - PR #$pr_number" \
      "**$pr_title**\nRebased on latest main.\n$pr_url" \
      65280  # green
    gh pr comment "$pr_number" --body "Rebased on latest \`main\` to resolve merge conflicts." \
      >>"$LOG_FILE" 2>&1 || true
  else
    git rebase --abort 2>>"$LOG_FILE" || true
    increment_counter "$counter_file" > /dev/null

    # Try cherry-pick recreation
    local pr_commits
    pr_commits=$(git log --reverse --format='%H' "origin/main..ORIG_HEAD" 2>/dev/null)

    if [[ -n "$pr_commits" ]]; then
      git checkout origin/main 2>>"$LOG_FILE" || { git checkout main 2>>"$LOG_FILE" || true; return; }
      git branch -D "$pr_branch" 2>>"$LOG_FILE" || true
      git checkout -b "$pr_branch" 2>>"$LOG_FILE" || { git checkout main 2>>"$LOG_FILE" || true; return; }

      local cherry_success=true
      while IFS= read -r commit_sha; do
        if ! git cherry-pick "$commit_sha" 2>>"$LOG_FILE"; then
          git cherry-pick --abort 2>>"$LOG_FILE" || true
          cherry_success=false
          break
        fi
      done <<< "$pr_commits"

      if [[ "$cherry_success" == "true" ]]; then
        git push --force-with-lease origin "$pr_branch" 2>>"$LOG_FILE" || { git checkout main 2>>"$LOG_FILE" || true; return; }
        log "PR #$pr_number: conflicts resolved via cherry-pick"
        reset_counter "$counter_file"
        notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
          "Conflicts Resolved - PR #$pr_number" \
          "**$pr_title**\nRecreated from latest main.\n$pr_url" \
          65280  # green
        gh pr comment "$pr_number" --body "Recreated branch from latest \`main\` via cherry-pick." \
          >>"$LOG_FILE" 2>&1 || true
      else
        log "PR #$pr_number: cherry-pick recreation failed"
      fi
    fi
  fi

  git checkout main 2>>"$LOG_FILE" || true
}

# --- Check Review Comments ---
_check_review_comments() {
  local pr_number="$1" pr_title="$2" pr_branch="$3" pr_url="$4"

  # Get review comments (from human reviewers)
  local comments
  comments=$(gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments" \
    --jq '[.[] | select(.user.type != "Bot")] | sort_by(.created_at) | last' \
    2>/dev/null) || return

  [[ -z "$comments" || "$comments" == "null" ]] && return

  local comment_body comment_id
  comment_body=$(echo "$comments" | jq -r '.body // empty')
  comment_id=$(echo "$comments" | jq -r '.id // empty')

  [[ -z "$comment_body" ]] && return

  # Skip if already addressed
  local marker_file="$LOG_DIR/.pr-comment-${pr_number}-last"
  local last_addressed=""
  [[ -f "$marker_file" ]] && last_addressed=$(cat "$marker_file")
  [[ "$comment_id" == "$last_addressed" ]] && return

  # Check retry counter
  local review_counter_file="$LOG_DIR/.pr-review-${pr_number}-count"
  local review_attempts
  review_attempts=$(cat "$review_counter_file" 2>/dev/null || echo "0")

  if [[ "$review_attempts" -ge "$MAX_REVIEW_ATTEMPTS" ]]; then
    local review_escalated_file="$LOG_DIR/.pr-review-${pr_number}-escalated"
    if [[ ! -f "$review_escalated_file" ]]; then
      escalate_to_human "$pr_number" "$pr_title" "$pr_url" \
        "Review feedback after $review_attempts fix attempts. Latest: ${comment_body:0:120}"
      touch "$review_escalated_file"
    fi
    echo "$comment_id" > "$marker_file"
    return
  fi

  log "PR #$pr_number has review comment (attempt $((review_attempts + 1))/$MAX_REVIEW_ATTEMPTS): ${comment_body:0:80}..."

  git fetch origin "$pr_branch" 2>>"$LOG_FILE" || return
  git checkout "$pr_branch" 2>>"$LOG_FILE" || return

  local review_prompt="You are a builder agent. A reviewer left this comment on your PR:

## PR: $pr_title
## Review Comment:
$comment_body

## File Context:
$(echo "$comments" | jq -r '.path // empty'): line $(echo "$comments" | jq -r '.line // .original_line // "unknown"')
$(echo "$comments" | jq -r '.diff_hunk // empty')

## Instructions
Address the reviewer's feedback. Make the requested changes.
$(cat "$INSTRUCTIONS_DIR/${ROLE}.md" 2>/dev/null || true)

## Workflow
1. Make the requested changes
2. Run tests to verify
3. Stage and commit with message: '[builder] Address review feedback on PR #$pr_number'
4. Do NOT push"

  local review_success=false

  if check_codex_available; then
    log "Addressing review with Codex CLI..."
    if codex exec --full-auto -C "$REPO_PATH" "$review_prompt" >>"$LOG_FILE" 2>&1; then
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git add -A
        git commit -m "[$ROLE] Address review feedback on PR #$pr_number

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
        git commit -m "[$ROLE] Address review feedback on PR #$pr_number

Feedback: ${comment_body:0:100}" 2>>"$LOG_FILE" && review_success=true
      fi
    fi
  fi

  increment_counter "$review_counter_file" > /dev/null

  if [[ "$review_success" == "true" ]]; then
    # Run local CI
    local review_ci=true
    if [[ -f "Makefile" ]] && grep -q '^test:' Makefile 2>/dev/null; then
      make test >>"$LOG_FILE" 2>&1 || review_ci=false
    elif [[ -f "package.json" ]]; then
      npm run build >>"$LOG_FILE" 2>&1 || review_ci=false
    fi

    git push origin "$pr_branch" 2>>"$LOG_FILE" || true

    gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
      -f body="Addressed in $(git rev-parse --short HEAD). Local CI: $([ "$review_ci" = "true" ] && echo "PASSED" || echo "FAILED") (attempt $((review_attempts + 1))/$MAX_REVIEW_ATTEMPTS)" \
      >>"$LOG_FILE" 2>&1 || true

    log "PR #$pr_number: review comment addressed, pushed fix"
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Review Addressed - PR #$pr_number" \
      "**$pr_title**\nAddressed feedback (attempt $((review_attempts + 1))/$MAX_REVIEW_ATTEMPTS).\n$pr_url" \
      5814783  # blue
  else
    log "PR #$pr_number: failed to address review comment"
    gh api "repos/{owner}/{repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
      -f body="I wasn't able to automatically address this feedback (attempt $((review_attempts + 1))/$MAX_REVIEW_ATTEMPTS)." \
      >>"$LOG_FILE" 2>&1 || true
  fi

  echo "$comment_id" > "$marker_file"
  git checkout main 2>>"$LOG_FILE" || true
}

# --- Main Polling Loop ---
# PR health check runs every PR_HEALTH_INTERVAL loops regardless of task availability
PR_HEALTH_INTERVAL=3   # check PRs every 3rd loop (~6 min at 2-min poll)
_loop_count=0

while true; do
  _loop_count=$((_loop_count + 1))
  log "Polling for tasks (loop #$_loop_count)..."

  TASK_JSON=$(poll_for_task)
  TASK_ID=$(echo "$TASK_JSON" | jq -r '.id // 0' 2>/dev/null || echo "0")

  if [[ "$TASK_ID" != "0" && "$TASK_ID" != "null" && -n "$TASK_ID" ]]; then
    TASK_TITLE=$(echo "$TASK_JSON" | jq -r '.title // "Untitled"' 2>/dev/null || echo "Untitled")
    TASK_DESC=$(echo "$TASK_JSON" | jq -r '.description // ""' 2>/dev/null || echo "")

    log "Found task #$TASK_ID: $TASK_TITLE"

    # Check if task is clear enough before claiming
    # If description is vague, auto_enrich_description will generate one
    ENRICHED_TASK_DESC=""
    if ! check_task_clarity "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"; then
      log "Task #$TASK_ID skipped — insufficient description and enrichment failed"
      sleep "$POLL_INTERVAL"
      continue
    fi

    # Use enriched description if auto-enrichment happened
    if [[ -n "$ENRICHED_TASK_DESC" ]]; then
      TASK_DESC="$ENRICHED_TASK_DESC"
      log "Task #$TASK_ID: using auto-enriched description (${#TASK_DESC} chars)"
    fi

    if ! claim_task "$TASK_ID"; then
      log "Task #$TASK_ID claimed by another builder — back to polling"
      sleep "$POLL_INTERVAL"
      continue
    fi

    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Claimed - #$TASK_ID" \
      "**$TASK_TITLE**\nAgent: \`$AGENT_ID\`" \
      5814783  # blue

    execute_task "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"

    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Complete - #$TASK_ID" \
      "**$TASK_TITLE**\nAgent: \`$AGENT_ID\`" \
      65280  # green

    log "Task #$TASK_ID complete, waiting ${POLL_INTERVAL}s before next poll"
  else
    log "No tasks found, sleeping ${POLL_INTERVAL}s"
  fi

  # Check for merged PRs every loop (~2 min) — lightweight, keeps Vikunja board accurate
  # Only one builder per machine does this (avoid 10 builders all checking)
  if [[ "$AGENT_ID" == "builder-1" || "$AGENT_ID" == "builder-11" ]]; then
    check_merged_prs
  fi

  # Run full PR health check (CI fix, conflict resolution, review comments) every PR_HEALTH_INTERVAL loops
  if (( _loop_count % PR_HEALTH_INTERVAL == 0 )); then
    log "Running PR health check (loop #$_loop_count)..."
    check_pr_health
  fi

  # Add jitter (0-15s) to prevent all builders polling at the exact same moment
  _jitter=$((RANDOM % 16))
  sleep $((POLL_INTERVAL + _jitter))
done
