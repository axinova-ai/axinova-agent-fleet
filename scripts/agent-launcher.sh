#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# Agent Launcher - Generic builder agent that polls Vikunja for tasks
# Usage: agent-launcher.sh <agent-id> <workspace-path> [poll-interval-seconds]
#
# All agents are generic builders — they pick up any unclaimed task.
# The task description specifies which repo(s) to work on.
#
# Example: agent-launcher.sh builder-1 ~/workspace 120
#
# LLM Strategy (updated 2026-03-13):
#   Automated (agents):
#     1. codex exec --full-auto (gpt-5.4) → primary automated coding
#     2. Ollama qwen2.5-coder (local) → only if MODEL: ollama set
#   Manual (founder, Needs Founder bucket):
#     - Codex CLI (interactive) or Claude Code CLI (Sonnet/Opus 4.6)
#   On failure → escalate to Needs Founder for manual pickup
#   Kimi K2.5 removed from builder chain — 5x more escalations than Codex

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
  local description="${3:-}"
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
  local description="${3:-}"
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
VIKUNJA_URL="${APP_VIKUNJA__URL:-http://localhost:3456}"
VIKUNJA_TOKEN="${APP_VIKUNJA__TOKEN:-}"

# Kanban bucket IDs (project 13, kanban view 52 — used as canonical bucket-purpose identifiers)
BUCKET_TODO=35
BUCKET_DOING=36
BUCKET_IN_REVIEW=39
BUCKET_NEEDS_FOUNDER=38
BUCKET_DONE=37

# Active task project context (cached per-task to avoid extra API calls in move_to_bucket)
ACTIVE_TASK_PROJECT_ID=0

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
  # Pipe through tr to strip control chars (U+0000-U+001F) except newline/tab/CR
  # that Vikunja HTML descriptions may contain, which break jq parsing.
  curl "${args[@]}" "${VIKUNJA_URL}/api/v1${endpoint}" 2>/dev/null | tr -d '\000-\010\013\014\016-\037'
}

# --- Vikunja Task Comments (audit trail) ---
add_task_comment() {
  local task_id="$1"
  local comment="$2"
  local timestamp
  timestamp="[$(date '+%Y-%m-%d %H:%M')]"
  local full_comment="${timestamp} ${comment}"
  local escaped_comment
  escaped_comment=$(printf '%s' "$full_comment" | jq -Rs .)
  vikunja_api PUT "/tasks/${task_id}/comments" \
    "{\"comment\":${escaped_comment}}" >/dev/null 2>&1 || true
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

  local system_msg="You are a code generation agent. Output ONLY a unified diff inside a \`\`\`diff code fence. No explanations. Keep reasoning minimal — prioritize generating the diff output."

  local response
  response=$(curl -sf --max-time 600 \
    "https://api.moonshot.cn/v1/chat/completions" \
    -H "Authorization: Bearer $MOONSHOT_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg system "$system_msg" \
      --arg prompt "$prompt" \
      --argjson max_tokens "$max_tokens" \
      '{
        model: "kimi-k2.5",
        messages: [
          {role: "system", content: $system},
          {role: "user", content: $prompt}
        ],
        max_tokens: $max_tokens,
        temperature: 0.7
      }')" 2>&1)

  if [[ $? -ne 0 || -z "$response" ]]; then
    log "ERROR: Kimi API call failed"
    return 1
  fi

  # kimi-k2.5 is a reasoning model: puts thinking in reasoning_content, answer in content.
  # If max_tokens is exhausted on reasoning, content is "" (empty string, not null).
  # jq's // operator only matches null, so we must explicitly check for empty string.
  local content
  content=$(echo "$response" | jq -r '.choices[0].message.content // ""')
  local finish_reason
  finish_reason=$(echo "$response" | jq -r '.choices[0].finish_reason // ""')

  if [[ -z "$content" ]]; then
    if [[ "$finish_reason" == "length" ]]; then
      log "ERROR: Kimi API exhausted max_tokens=$max_tokens on reasoning (content empty, finish_reason=length)"
    else
      log "ERROR: Kimi API returned empty content (finish_reason=$finish_reason)"
    fi
    return 1
  fi

  echo "$content"
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
  local task_desc="${2:-}"

  # Priority 1: Explicit MODEL: directive in task description
  # Supported values: codex, kimi, ollama, founder
  # Usage in Vikunja task description: <p><strong>MODEL:</strong> codex</p>
  # "founder" means human-only — agents must not execute (should be caught earlier
  # in check_task_validity, but this is a safety net).
  local model_override=""
  model_override=$(echo "$task_desc" | sed "s/<[^>]*>//g" | grep -oiE "MODEL:[[:space:]]*(codex|kimi|ollama|founder)" | head -1 | sed "s/MODEL:[[:space:]]*//I" | tr "[:upper:]" "[:lower:]") || true
  if [[ -n "$model_override" ]]; then
    if [[ "$model_override" == "founder" ]]; then
      log "ERROR: MODEL: founder task reached select_model — should have been filtered in check_task_validity. Aborting."
      echo "founder"
      return 1
    fi
    log "Model override from task description: $model_override"
    echo "$model_override"
    return
  fi

  # Priority 2: Default → codex exec (primary automated model)
  # Kimi fallback removed — 5x more escalations than Codex, often exits with 0 changes.
  # If Codex fails, escalate directly to Needs Founder for manual Claude Code CLI pickup.
  # Ollama only runs if explicitly requested via MODEL: ollama override.
  echo "codex"
}

estimate_complexity() {
  local title="$1" desc="$2" priority="${3:-0}"
  local score=0
  local text="$title $desc"

  # Priority-based routing (set at task design time by founder using Opus):
  #   1=trivial, 2=simple, 3=medium → agent-eligible
  #   4=hard, 5=founder-only → auto-escalate immediately
  if [[ "$priority" -ge 4 ]]; then
    echo "$priority"
    return
  fi

  # Multi-component signals (+2 each)
  echo "$text" | grep -qiE 'wizard|onboarding|migration|refactor|redesign|admin panel' && score=$((score + 2))
  echo "$text" | grep -qiE 'multi.*(step|page|component|file)' && score=$((score + 2))

  # Scope signals (+1 each)
  echo "$text" | grep -qiE 'crud|handler.*route|middleware' && score=$((score + 1))
  echo "$text" | grep -qiE 'upload|oss|payment|security' && score=$((score + 1))

  # Acceptance criteria count (+2 if >5 items)
  local criteria_count
  criteria_count=$(echo "$desc" | grep -ciE '^[[:space:]]*[-*][[:space:]]|<li>' || echo 0)
  [[ "$criteria_count" -gt 5 ]] && score=$((score + 2))

  # Multiple file references (+1 if >3)
  local file_count
  file_count=$(echo "$desc" | grep -coE '.(vue|go|ts|sql)' || echo 0)
  [[ "$file_count" -gt 3 ]] && score=$((score + 1))

  echo "$score"
}
# Codex exec model (configurable via env)
CODEX_MODEL="${CODEX_MODEL:-gpt-5.4}"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-600}"  # 10 min timeout (complex multi-file tasks need more time)
KIMI_TIMEOUT="${KIMI_TIMEOUT:-600}"    # 10 min timeout for Kimi CLI

# Portable timeout: macOS has no GNU timeout, use perl fallback
_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    # perl-based timeout for macOS
    perl -e '
      alarm shift @ARGV;
      $SIG{ALRM} = sub { kill 9, $pid; exit 124 };
      $pid = fork // die;
      if ($pid == 0) { exec @ARGV; die "exec: $!" }
      waitpid $pid, 0;
      exit ($? >> 8);
    ' "$secs" "$@"
  fi
}

# Check if Codex CLI is available (searches common npm-global locations launchd may miss)
check_codex_available() {
  if command -v codex >/dev/null 2>&1; then
    return 0
  fi
  # Fallback: check common npm-global install paths not always in launchd PATH
  local candidate
  for candidate in \
    "$HOME/.npm-global/bin/codex" \
    "$HOME/.local/bin/codex" \
    "/usr/local/bin/codex" \
    "$(npm bin -g 2>/dev/null)/codex"; do
    if [[ -x "$candidate" ]]; then
      # Inject into PATH so subsequent calls find it without the loop
      export PATH="$(dirname "$candidate"):$PATH"
      return 0
    fi
  done
  return 1
}

# Check if Kimi CLI is available
check_kimi_cli_available() {
  if command -v kimi >/dev/null 2>&1; then
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/.local/bin/kimi" \
    "$HOME/.local/share/uv/tools/kimi-cli/bin/kimi" \
    "/usr/local/bin/kimi"; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      return 0
    fi
  done
  return 1
}

# --- Codex Audit Logging ---
# Structured JSONL audit log for every Codex invocation
CODEX_AUDIT_LOG="$LOG_DIR/codex-audit.jsonl"

log_codex_audit() {
  local task_id="$1"
  local invocation_type="$2"  # initial|ci-fix|pr-ci-fix|review-fix|wiki
  local exit_code="$3"
  local duration_secs="$4"
  local pr_number="${5:-}"
  echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"agent\":\"$AGENT_ID\",\"task_id\":\"$task_id\",\"type\":\"$invocation_type\",\"model\":\"$CODEX_MODEL\",\"exit_code\":$exit_code,\"duration_secs\":$duration_secs,\"pr\":\"$pr_number\",\"host\":\"$(hostname -s)\"}" >> "$CODEX_AUDIT_LOG"
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

  # Gather repo context: file tree (depth 3), recent git log, key file contents
  # Use WORK_DIR (worktree) if set, otherwise fall back to REPO_PATH
  local _ctx_dir="${WORK_DIR:-$REPO_PATH}"
  local file_tree recent_log key_files_content
  file_tree=$(find "$_ctx_dir" -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -100 2>/dev/null || true)
  recent_log=$(git -C "$_ctx_dir" log --oneline -5 2>/dev/null || true)

  # Include contents of files likely to be modified (Makefile, main.go, relevant source)
  # This gives the LLM accurate context lines for diffs
  key_files_content=""
  local _kf
  for _kf in Makefile go.mod cmd/service/main.go cmd/seed/main.go scripts/seed-dev.go package.json src/main.ts; do
    if [[ -f "$_ctx_dir/$_kf" ]]; then
      local _content
      _content=$(head -80 "$_ctx_dir/$_kf" 2>/dev/null || true)
      if [[ -n "$_content" ]]; then
        key_files_content="${key_files_content}
### File: $_kf
\`\`\`
$_content
\`\`\`
"
      fi
    fi
  done

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
$key_files_content
## Output Format

IMPORTANT: For NEW files, use \`--- /dev/null\` and \`+++ b/path/to/new/file\`.
Only use \`--- a/path\` when MODIFYING an existing file — and match the context lines EXACTLY as shown above.

Your ENTIRE response must be a SINGLE code block — nothing before it, nothing after it.
Start your response with exactly: \`\`\`diff
End your response with exactly: \`\`\`

The block must contain a unified diff applicable with \`git apply\`:

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
- Use correct relative paths from repo root (no leading /)
- For new files: \`--- /dev/null\` and \`+++ b/path/to/new/file\`
- For deleted files: \`--- a/path/to/file\` and \`+++ /dev/null\`
- If modifying multiple files, include all hunks in one diff block
- Do NOT output any explanation, reasoning, or commentary — ONLY the \`\`\`diff block
PROMPT
}

# Extract diff from LLM output (handles markdown fences)
extract_diff() {
  local output="$1"
  # Try to extract from ```diff ... ``` fences first (tolerant: allow trailing spaces, language hints)
  local extracted
  extracted=$(printf '%s\n' "$output" | sed -n '/^```diff/,/^```[[:space:]]*$/p' | sed '1d;$d')
  if [[ -n "$extracted" ]]; then
    printf '%s\n' "$extracted"
    return
  fi
  # Try ``` ... ``` fences (any language or plain)
  extracted=$(printf '%s\n' "$output" | sed -n '/^```/,/^```[[:space:]]*$/p' | sed '1d;$d')
  if [[ -n "$extracted" ]]; then
    printf '%s\n' "$extracted"
    return
  fi
  # Try to extract just the diff lines (--- a/, +++ b/, @@, +, -, space-prefixed context)
  extracted=$(printf '%s\n' "$output" | sed -n '/^--- /,/^$/p' | head -500)
  if printf '%s' "$extracted" | grep -q '^@@'; then
    printf '%s\n' "$extracted"
    return
  fi
  # Log what we got for debugging
  log "WARNING: extract_diff could not find fenced or raw diff. First 300 chars: ${output:0:300}"
  printf '%s\n' "$output"
}

# Apply unified diff to repo
apply_diff() {
  local diff_content="$1"
  local task_id="$2"

  if [[ -z "$diff_content" || "$diff_content" == "null" ]]; then
    log "WARNING: Empty diff output from LLM"
    return 1
  fi

  cd "${WORK_DIR:-$REPO_PATH}"

  # Write diff to temp file
  local diff_file
  diff_file=$(mktemp /tmp/agent-diff-XXXXXX.patch)
  printf '%s\n' "$diff_content" > "$diff_file"

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

# --- Git Worktree Helpers ---
# Each agent task gets an isolated worktree so multiple agents can work on the
# same repo simultaneously without interfering with each other.
WORKTREE_BASE="$HOME/worktrees"
mkdir -p "$WORKTREE_BASE"

# Create a new worktree branching from origin/main.
# Usage: setup_worktree <repo_path> <branch_name>
# Prints: the worktree directory path
setup_worktree() {
  local repo_path="$1"
  local branch_name="$2"
  local repo_name
  repo_name=$(basename "$repo_path")
  # Flatten branch slashes to dashes for the directory name
  local worktree_dir="$WORKTREE_BASE/${repo_name}/${branch_name//\//-}"

  # Clean up stale worktree if it exists from a previous run
  if [[ -d "$worktree_dir" ]]; then
    git -C "$repo_path" worktree remove --force "$worktree_dir" 2>/dev/null || rm -rf "$worktree_dir"
  fi

  # Fetch latest main
  git -C "$repo_path" fetch origin main 2>>"$LOG_FILE" || true

  # Delete the local branch if it exists (stale from previous attempt)
  git -C "$repo_path" branch -D "$branch_name" 2>/dev/null || true

  # Create worktree with a new branch from origin/main
  mkdir -p "$(dirname "$worktree_dir")"
  if git -C "$repo_path" worktree add "$worktree_dir" -b "$branch_name" origin/main >>"$LOG_FILE" 2>&1; then
    # NOTE: log() uses tee→stdout. This function is called as $(setup_worktree ...),
    # so ALL stdout is captured. Redirect log to stderr to keep return value clean.
    log "Worktree created: $worktree_dir (branch: $branch_name)" >&2
  else
    log "ERROR: Failed to create worktree for $branch_name" >&2
    return 1
  fi

  echo "$worktree_dir"
}

# Create a worktree for an existing remote branch (e.g., PR fixes).
# Usage: setup_worktree_existing <repo_path> <branch_name>
# Prints: the worktree directory path
setup_worktree_existing() {
  local repo_path="$1"
  local branch_name="$2"
  local repo_name
  repo_name=$(basename "$repo_path")
  local worktree_dir="$WORKTREE_BASE/${repo_name}/${branch_name//\//-}"

  # Clean up stale worktree
  if [[ -d "$worktree_dir" ]]; then
    git -C "$repo_path" worktree remove --force "$worktree_dir" 2>/dev/null || rm -rf "$worktree_dir"
  fi

  git -C "$repo_path" fetch origin "$branch_name" main 2>>"$LOG_FILE" || true

  # Delete stale local branch so checkout tracks remote
  git -C "$repo_path" branch -D "$branch_name" 2>/dev/null || true

  mkdir -p "$(dirname "$worktree_dir")"
  if git -C "$repo_path" worktree add --track -b "$branch_name" "$worktree_dir" "origin/$branch_name" >>"$LOG_FILE" 2>&1; then
    log "Worktree created (existing branch): $worktree_dir (branch: $branch_name)" >&2
  else
    log "ERROR: Failed to create worktree for existing branch $branch_name" >&2
    return 1
  fi

  echo "$worktree_dir"
}

# Remove a worktree and its local branch.
# Usage: cleanup_worktree <repo_path> <worktree_dir>
cleanup_worktree() {
  local repo_path="$1"
  local worktree_dir="$2"
  if [[ -n "$worktree_dir" && -d "$worktree_dir" ]]; then
    git -C "$repo_path" worktree remove --force "$worktree_dir" 2>>"$LOG_FILE" || rm -rf "$worktree_dir"
    log "Worktree removed: $worktree_dir"
  fi
}

log "Starting agent: id=$AGENT_ID workspace=$WORKSPACE poll=${POLL_INTERVAL}s"
log "Models available: codex-exec=$(check_codex_available && echo "yes($CODEX_MODEL)" || echo 'no') ollama=$(curl -sf "${OLLAMA_HOST:-http://localhost:11434}/api/tags" >/dev/null 2>&1 && echo 'yes' || echo 'no')"

# --- Multi-project support ---
# Agents poll tasks from project 13 (agent-fleet) and any project whose title ends with -ag.
# Each project has its own kanban view and bucket IDs, stored as colon-delimited config lines:
#   project_id:view_id:bucket_todo:bucket_doing:bucket_in_review:bucket_needs_founder:bucket_done
# Config is persisted in a temp file (no bash 4 associative arrays — macOS compat).

PROJECT_CONFIG_FILE="/tmp/agent-launcher-project-configs-${AGENT_ID:-default}"

# Helper to parse a field from a colon-delimited project config string
# Fields: 1=project_id, 2=view_id, 3=bucket_todo, 4=bucket_doing,
#         5=bucket_in_review, 6=bucket_needs_founder, 7=bucket_done
get_project_field() {
  local config="$1" field_idx="$2"
  echo "$config" | cut -d: -f"$field_idx"
}

# Lookup project config by project_id from the config file
get_project_config() {
  local target_pid="$1"
  if [[ ! -f "$PROJECT_CONFIG_FILE" ]]; then
    return 1
  fi
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid
    pid=$(get_project_field "$line" 1)
    if [[ "$pid" == "$target_pid" ]]; then
      echo "$line"
      return 0
    fi
  done < "$PROJECT_CONFIG_FILE"
  return 1
}

# Discover kanban view and bucket IDs for a single project
discover_project_config() {
  local project_id="$1"

  # Find the first kanban view for this project
  local views
  views=$(vikunja_api GET "/projects/$project_id/views" 2>/dev/null) || return 1

  local kanban_view_id
  kanban_view_id=$(echo "$views" | jq -r '[.[] | select(.view_kind == "kanban")] | .[0].id // 0' 2>/dev/null) || return 1

  if [[ "$kanban_view_id" == "0" || -z "$kanban_view_id" ]]; then
    log "Project #$project_id has no kanban view — skipping"
    return 1
  fi

  # Get buckets for this kanban view
  local buckets
  buckets=$(vikunja_api GET "/projects/$project_id/views/$kanban_view_id/buckets" 2>/dev/null) || return 1

  # Map bucket names to IDs (case-insensitive matching)
  local b_todo b_doing b_in_review b_needs_founder b_done
  b_todo=$(echo "$buckets" | jq -r '[.[] | select(.title | test("to.?do"; "i"))] | .[0].id // 0' 2>/dev/null) || b_todo=0
  b_doing=$(echo "$buckets" | jq -r '[.[] | select(.title | test("doing"; "i"))] | .[0].id // 0' 2>/dev/null) || b_doing=0
  b_in_review=$(echo "$buckets" | jq -r '[.[] | select(.title | test("review"; "i"))] | .[0].id // 0' 2>/dev/null) || b_in_review=0
  b_needs_founder=$(echo "$buckets" | jq -r '[.[] | select(.title | test("founder"; "i"))] | .[0].id // 0' 2>/dev/null) || b_needs_founder=0
  b_done=$(echo "$buckets" | jq -r '[.[] | select(.title | test("done"; "i"))] | .[0].id // 0' 2>/dev/null) || b_done=0

  # Require at least To-Do and Doing buckets
  if [[ "$b_todo" == "0" || "$b_doing" == "0" ]]; then
    log "Project #$project_id missing required buckets (To-Do=$b_todo, Doing=$b_doing) — skipping"
    return 1
  fi

  echo "${project_id}:${kanban_view_id}:${b_todo}:${b_doing}:${b_in_review}:${b_needs_founder}:${b_done}"
}

# Discover all eligible projects at startup and write config file
discover_eligible_projects() {
  log "Discovering eligible projects..."
  : > "$PROJECT_CONFIG_FILE"  # truncate

  # Always include project 13 (agent-fleet) with known config
  echo "13:52:${BUCKET_TODO}:${BUCKET_DOING}:${BUCKET_IN_REVIEW}:${BUCKET_NEEDS_FOUNDER}:${BUCKET_DONE}" >> "$PROJECT_CONFIG_FILE"
  log "  Project 13 (agent-fleet): hardcoded config"

  # Discover additional -ag projects
  local projects
  projects=$(vikunja_api GET "/projects" 2>/dev/null) || { log "Failed to list projects"; return; }

  local ag_line pid ptitle config
  # Extract id:title pairs for projects whose title ends with -ag
  while IFS= read -r ag_line; do
    [[ -z "$ag_line" ]] && continue
    pid=$(echo "$ag_line" | cut -d'|' -f1)
    ptitle=$(echo "$ag_line" | cut -d'|' -f2)
    [[ -z "$pid" ]] && continue
    [[ "$pid" == "13" ]] && continue  # Already added

    config=$(discover_project_config "$pid") || continue
    echo "$config" >> "$PROJECT_CONFIG_FILE"
    log "  Project $pid ($ptitle): auto-discovered config"
  done <<< "$(echo "$projects" | jq -r '.[] | select(.title | test("-ag$")) | "\(.id)|\(.title)"' 2>/dev/null || true)"

  local total
  total=$(wc -l < "$PROJECT_CONFIG_FILE" | tr -d ' ')
  log "Eligible projects: $total total"
}

# Map a project-13 bucket ID to the equivalent bucket purpose for any project.
# Returns the correct bucket_id for the target project.
# If the target project is 13 or not in config, returns the original bucket_id unchanged.
resolve_bucket_for_project() {
  local target_project_id="$1"
  local p13_bucket_id="$2"

  # Fast path: project 13 uses the original IDs
  if [[ "$target_project_id" == "13" ]]; then
    echo "$p13_bucket_id"
    return
  fi

  local config
  config=$(get_project_config "$target_project_id") || { echo "$p13_bucket_id"; return; }

  # Determine which bucket purpose this p13 bucket_id maps to
  local field_idx=""
  case "$p13_bucket_id" in
    "$BUCKET_TODO") field_idx=3 ;;
    "$BUCKET_DOING") field_idx=4 ;;
    "$BUCKET_IN_REVIEW") field_idx=5 ;;
    "$BUCKET_NEEDS_FOUNDER") field_idx=6 ;;
    "$BUCKET_DONE") field_idx=7 ;;
    *) echo "$p13_bucket_id"; return ;;  # Unknown bucket, pass through
  esac

  local resolved
  resolved=$(get_project_field "$config" "$field_idx")
  if [[ -z "$resolved" || "$resolved" == "0" ]]; then
    # Target project doesn't have this bucket; fall back to original
    echo "$p13_bucket_id"
  else
    echo "$resolved"
  fi
}

# --- Wave-Gating ---
# Labels matching *-wave-N gate task pickup order within a project.
# For each wave prefix (e.g., "steel"), only the lowest incomplete wave is eligible.
# Tasks without a wave label are always eligible (no gating).
# A wave is "incomplete" if ANY of its tasks across ALL buckets are not done.
filter_by_wave_gate() {
  local todo_candidates="$1"    # JSON array: tasks in To-Do with percent_done==0
  local all_undone="$2"         # JSON array: all undone tasks across all buckets

  # Step 1: Extract min wave per prefix from all undone tasks (tiny JSON, safe for --argjson).
  # Passing full all_undone (~80KB) as --argjson hits shell ARG_MAX limits on macOS.
  local min_waves
  min_waves=$(echo "$all_undone" | jq -c '
    [.[].labels[]?.title // empty]
    | map(capture("^(?<pfx>.+)-wave-(?<num>[0-9]+)$") // empty)
    | map({prefix: .pfx, num: (.num | tonumber)})
    | group_by(.prefix)
    | map({key: .[0].prefix, value: (map(.num) | min)})
    | from_entries
  ' 2>/dev/null) || min_waves="{}"

  [[ -z "$min_waves" || "$min_waves" == "null" ]] && min_waves="{}"

  # Step 2: Filter candidates using the small min_waves map
  echo "$todo_candidates" | jq -c --argjson mw "$min_waves" '
    def wave_info:
      [.labels[]?.title // empty]
      | map(capture("^(?<pfx>.+)-wave-(?<num>[0-9]+)$") // empty)
      | map({prefix: .pfx, num: (.num | tonumber)});

    [.[] | . as $task |
      ($task | wave_info) as $task_waves |
      if ($task_waves | length) == 0 then
        $task
      elif ($task_waves | all(. as $w | $mw[$w.prefix] == $w.num)) then
        $task
      else
        empty
      end
    ]
  ' 2>/dev/null || echo "$todo_candidates"
}

# --- Task Polling ---
# Uses the Kanban view API to fetch ONLY tasks in the To-Do bucket.
# Any task in To-Do (regardless of percent_done) is eligible for pickup.
# Tasks in Doing/Done/In Review/Needs Founder are NOT picked up.
# Wave-gated: within each project, only the lowest incomplete wave is eligible.

# Run project discovery at startup
discover_eligible_projects

poll_for_task() {
  # Iterate through all eligible projects in random order.
  # Returns the first eligible task found (as JSON with project_id).
  if [[ ! -f "$PROJECT_CONFIG_FILE" ]]; then
    echo '{"id": 0}'
    return
  fi

  local shuffled_configs
  # macOS sort lacks -R; use awk+RANDOM to shuffle (fallback: unshuffled)
  shuffled_configs=$(awk 'BEGIN{srand()} {print rand()"\t"$0}' "$PROJECT_CONFIG_FILE" | sort -n | cut -f2-) || shuffled_configs=$(cat "$PROJECT_CONFIG_FILE")

  local config pid view_id b_todo
  while IFS= read -r config; do
    [[ -z "$config" ]] && continue
    pid=$(get_project_field "$config" 1)
    view_id=$(get_project_field "$config" 2)
    b_todo=$(get_project_field "$config" 3)

    local view_data
    # Sanitize: Vikunja can return bare control chars in HTML descriptions that break jq
    view_data=$(vikunja_api GET "/projects/$pid/views/$view_id/tasks?per_page=50" 2>/dev/null | python3 -c "
import sys
raw = sys.stdin.buffer.read()
sys.stdout.buffer.write(bytes(b if b >= 32 or b in (10, 13, 9) else 32 for b in raw))
" 2>/dev/null) || continue

    local candidates
    candidates=$(echo "$view_data" | jq -c --argjson todo "$b_todo" '
      [.[] | select(.id == $todo) | .tasks[]? | select(.done == false and .percent_done == 0)]
    ' 2>/dev/null) || continue

    # Wave-gating: only pick tasks from the lowest incomplete wave per prefix.
    # Labels like "steel-wave-3" or "auth-wave-1" are parsed as prefix="steel" wave=3.
    # Tasks with no wave label are always eligible.
    # A wave is "complete" only when ALL its tasks across ALL buckets are done.
    local all_undone
    all_undone=$(echo "$view_data" | jq -c '
      [.[] | .tasks[]? | select(.done == false)]
    ' 2>/dev/null) || all_undone="[]"

    local pre_gate_count
    pre_gate_count=$(echo "$candidates" | jq 'length' 2>/dev/null || echo "0")

    candidates=$(filter_by_wave_gate "$candidates" "$all_undone") || candidates="[]"

    local count
    count=$(echo "$candidates" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$pre_gate_count" -gt 0 && "$count" != "$pre_gate_count" ]]; then
      local active_waves
      active_waves=$(echo "$all_undone" | jq -r '
        [.[].labels[]?.title // empty]
        | map(capture("^(?<pfx>.+)-wave-(?<num>[0-9]+)$") // empty)
        | group_by(.prefix) | map(.[0].prefix + "-wave-" + (map(.num | tonumber) | min | tostring))
        | join(", ")
      ' 2>/dev/null || echo "unknown")
      # Log to file only (not stdout) — poll_for_task returns JSON on stdout
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$AGENT_ID] Wave-gate project $pid: $pre_gate_count To-Do → $count eligible (active: $active_waves)" >> "$LOG_FILE"
    fi

    if [[ "$count" -gt 0 && "$count" != "null" ]]; then
      local idx=$(( RANDOM % count ))
      local selected
      selected=$(echo "$candidates" | jq -c ".[$idx]")
      if [[ -n "$selected" && "$selected" != "null" ]]; then
        echo "$selected"
        return
      fi
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$AGENT_ID] DEBUG: wave-gate count=$count idx=$idx but jq returned empty for project $pid" >> "$LOG_FILE"
    fi
  done <<< "$shuffled_configs"

  echo '{"id": 0}'
}

claim_task() {
  local task_id="$1"

  # Random delay (1-15s) to reduce stampede when multiple builders poll simultaneously.
  # With 16 agents, 0-5s wasn't enough — agents still race on the same task.
  local delay=$(( (RANDOM % 15) + 1 ))
  log "Claim delay ${delay}s for task #$task_id"
  sleep "$delay"

  # Re-check: if another builder already claimed (0.5), started (0.9), or escalated,
  # skip it. Only pick up tasks at exactly percent_done=0.
  local current
  current=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true
  local current_pct
  current_pct=$(echo "$current" | jq -r '.percent_done // 0' 2>/dev/null)
  if [[ "$current_pct" != "0" ]]; then
    log "Task #$task_id already in progress or escalated (percent_done=$current_pct) — skipping"
    return 1
  fi

  log "Claiming task #$task_id (was at percent_done=$current_pct)"
  update_vikunja_task "$task_id" "{\"percent_done\": 0.5}"
  move_to_bucket "$task_id" "$BUCKET_DOING"
  add_task_comment "$task_id" "[CLAIMED] Agent $AGENT_ID on $(hostname -s) picking up task (previous progress: ${current_pct})"
  return 0
}

# Update Vikunja task (POST for update)
# IMPORTANT: Vikunja POST replaces ALL fields. We must preserve description/title
# if they are not explicitly included in the update payload.
# FIX: Use jq --arg (not --argjson) to avoid double-escaping HTML descriptions.
update_vikunja_task() {
  local task_id="$1"
  local data="$2"

  # GET existing task to preserve ALL fields (Vikunja POST /tasks/{id} replaces ALL fields).
  # Full merge: existing task is the base, patch fields override. This preserves
  # percent_done, priority, due_date, title, description — not just title+description.
  local existing
  existing=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true

  if [[ -n "$existing" ]]; then
    local merged
    # jq '. + $patch' = shallow merge, patch values win on conflict
    merged=$(echo "$existing" | jq --argjson patch "$data" '. + $patch' 2>/dev/null) || true
    if [[ -n "$merged" ]]; then
      data="$merged"
    fi
  fi

  vikunja_api POST "/tasks/${task_id}" "$data" >>"$LOG_FILE" 2>&1 || true
}

# Move task to a kanban bucket (project-aware: looks up task's project and resolves correct view/bucket)
# bucket_id is always passed as a project-13 BUCKET_* constant; this function translates
# it to the correct bucket ID for the task's actual project.
move_to_bucket() {
  local task_id="$1"
  local bucket_id="$2"

  # Use cached project ID if available (set in main loop), otherwise fetch
  local task_project_id="${ACTIVE_TASK_PROJECT_ID:-0}"
  if [[ "$task_project_id" == "0" ]]; then
    local task_data
    task_data=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null) || task_data=""
    task_project_id=$(echo "$task_data" | jq -r '.project_id // 0' 2>/dev/null) || task_project_id=0
  fi

  # Look up the project's view and resolve the bucket ID
  local config view_id resolved_bucket
  config=$(get_project_config "$task_project_id") || config=""

  if [[ -n "$config" ]]; then
    view_id=$(get_project_field "$config" 2)
    resolved_bucket=$(resolve_bucket_for_project "$task_project_id" "$bucket_id")
    vikunja_api POST "/projects/${task_project_id}/views/${view_id}/buckets/${resolved_bucket}/tasks" \
      "{\"task_id\": $task_id}" >>"$LOG_FILE" 2>&1 || true
  else
    # Fallback to project 13 defaults if project not in config
    log "WARN: Task #$task_id project $task_project_id not in config, falling back to project 13"
    vikunja_api POST "/projects/13/views/52/buckets/${bucket_id}/tasks" \
      "{\"task_id\": $task_id}" >>"$LOG_FILE" 2>&1 || true
  fi
}

# Check if task description has enough clarity for execution
# Returns 0 if task is actionable, 1 if too vague
# Auto-enrich a vague task description by analyzing the repo
# Uses Codex CLI or Kimi to generate a proper description from the task title + repo context
auto_enrich_description() {
  local task_id="$1"
  local task_title="$2"
  local repo_path="$3"

  # Safety guard: never overwrite structured descriptions (MODEL/TIER/BENCHMARK/SCOPE tags)
  local current_desc
  current_desc=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null | jq -r '.description // ""' 2>/dev/null) || true
  local plain_guard
  plain_guard=$(echo "$current_desc" | sed 's/<[^>]*>//g') || true
  if echo "$plain_guard" | grep -qiE 'MODEL:|TIER:|BENCHMARK|SCOPE:'; then
    log "Task #$task_id: description has structured tags — skipping auto-enrichment to preserve MODEL/TIER routing"
    echo "$current_desc"
    return 0
  fi

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

  # Re-fetch full task description from individual endpoint
  # Kanban view API may return truncated or stale descriptions
  local full_task
  full_task=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true
  if [[ -n "$full_task" ]]; then
    local fetched_desc
    fetched_desc=$(echo "$full_task" | jq -r '.description // ""' 2>/dev/null) || true
    if [[ -n "$fetched_desc" && ${#fetched_desc} -gt ${#task_description} ]]; then
      task_description="$fetched_desc"
      log "Task #$task_id: re-fetched description from API (${#task_description} chars)"
    fi
  fi

  # Wiki tasks need WIKI_PAGES: in description
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

  # Skip auto-enrichment if description has structured tags (MODEL/TIER/BENCHMARK/SCOPE)
  # These are well-defined tasks — do NOT overwrite with auto-generated text
  local plain_check
  plain_check=$(echo "$task_description" | sed 's/<[^>]*>//g') || true
  if echo "$plain_check" | grep -qiE 'MODEL:|TIER:|BENCHMARK|SCOPE:'; then
    log "Task #$task_id: has structured tags (MODEL/TIER/BENCHMARK/SCOPE), skipping enrichment"
    ENRICHED_TASK_DESC="$task_description"
    return 0
  fi

  # Auto-enrich if description is empty or too short
  if [[ -z "$task_description" || ${#task_description} -lt 20 ]]; then
    log "Task #$task_id: description too short (${#task_description} chars) — attempting auto-enrichment"

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

# Lightweight pre-claim validity check — no LLM calls, no enrichment comments.
# Only rejects tasks that are fundamentally broken (wrong structure).
# Enrichment happens AFTER claiming to avoid comment spam from multiple agents.
check_task_validity() {
  local task_id="$1"
  local task_title="$2"
  local task_description="$3"

  # Re-fetch full description (kanban view may truncate)
  local full_desc
  full_desc=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null | jq -r '.description // ""' 2>/dev/null) || true
  if [[ -n "$full_desc" && ${#full_desc} -gt ${#task_description} ]]; then
    task_description="$full_desc"
  fi

  # Tasks with MODEL: founder are reserved for manual human work — agents must skip
  local stripped_desc
  stripped_desc=$(echo "$task_description" | sed 's/<[^>]*>//g') || true
  if echo "$stripped_desc" | grep -qiE "MODEL:[[:space:]]*founder"; then
    log "Task #$task_id: MODEL: founder — reserved for manual work, skipping"
    return 1
  fi

  # Wiki tasks must have WIKI_PAGES: field
  if is_wiki_task "$task_title" "$task_description"; then
    if ! echo "$task_description" | grep -q "WIKI_PAGES:"; then
      log "Task #$task_id: wiki task but no WIKI_PAGES: — skipping"
      return 1
    fi
    return 0
  fi

  # Code tasks must have a repo name (axinova-*) in title or description
  if ! echo "$task_title $task_description" | grep -qE 'axinova-[a-zA-Z0-9_-]+'; then
    log "Task #$task_id: no repo name found — skipping"
    return 1
  fi

  # Check for unmet task dependencies (blocked relations)
  # Vikunja embeds related_tasks in the full task GET response.
  # If any task in related_tasks.blocked has done=false, skip this task.
  local full_task_json
  full_task_json=$(vikunja_api GET "/tasks/${task_id}" 2>/dev/null) || true
  if [[ -n "$full_task_json" ]]; then
    local blocked_undone
    blocked_undone=$(echo "$full_task_json" | jq '[(.related_tasks.blocked // [])[] | select(.done == false)] | length' 2>/dev/null) || blocked_undone="0"
    if [[ "$blocked_undone" -gt 0 ]]; then
      log "Task #$task_id: blocked by $blocked_undone incomplete task(s) — skipping"
      return 1
    fi
  fi

  return 0
}

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

  # Create isolated worktree for this wiki task
  local branch_name="agent/${AGENT_ID}/task-${task_id}"
  local WORK_DIR=""
  WORK_DIR=$(setup_worktree "$REPO_PATH" "$branch_name") || true
  if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    log "ERROR: Failed to create worktree for wiki task #$task_id"
    escalate_task_to_founder "$task_id" "$task_title" "Worktree creation failed for wiki task in $REPO_NAME."
    return
  fi
  add_task_comment "$task_id" "[STARTED] Wiki task | Model: codex-exec/$CODEX_MODEL | Agent: $AGENT_ID"

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

    local wiki_codex_start wiki_codex_end wiki_codex_exit
    wiki_codex_start=$(date +%s)
    if _timeout "$CODEX_TIMEOUT" codex exec --full-auto -C "$WORK_DIR" "$codex_prompt" >>"$LOG_FILE" 2>&1; then
      wiki_codex_exit=0
      wiki_codex_end=$(date +%s)
      log_codex_audit "$task_id" "wiki" "0" "$((wiki_codex_end - wiki_codex_start))"
      log "Codex wiki task completed ($((wiki_codex_end - wiki_codex_start))s)"
      execution_success=true
    else
      wiki_codex_exit=$?
      wiki_codex_end=$(date +%s)
      log_codex_audit "$task_id" "wiki" "$wiki_codex_exit" "$((wiki_codex_end - wiki_codex_start))"
      if [[ "$wiki_codex_exit" -eq 124 ]]; then
        log "Codex wiki task TIMED OUT after ${CODEX_TIMEOUT}s — escalating to Needs Founder"
      else
        log "Codex wiki task failed (exit $wiki_codex_exit) — escalating to Needs Founder"
      fi
    fi
  fi

  # --- Kimi K2.5 wiki fallback removed (2026-03-13) ---
  # Kimi had 5x more escalations than Codex. If Codex fails, escalate to Needs Founder.

  # Handle any git changes (docs/ files created by Codex)
  cd "$WORK_DIR"
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
      # Repo changes → push + PR (already on task branch via worktree)
      local branch_name="agent/${AGENT_ID}/task-${task_id}"
      git push -u origin "$branch_name" 2>>"$LOG_FILE" || true
      local pr_url
      pr_url=$(gh pr create \
        --head "$branch_name" \
        --title "[builder] Task #${task_id}: ${task_title}" \
        --body "Wiki + repo update. Vikunja task #${task_id}. Duration: ${duration_str}." \
        --base main 2>>"$LOG_FILE") || true
      local result_msg="[COMPLETED] Wiki + repo changes | Model: codex-exec/$CODEX_MODEL | Duration: ${duration_str} | Agent: $AGENT_ID"
      [[ -n "$pr_url" ]] && result_msg+=" | PR: $pr_url"
      move_to_bucket "$task_id" "$BUCKET_IN_REVIEW"
      add_task_comment "$task_id" "$result_msg"
    else
      # Wiki-only → move straight to Done
      move_to_bucket "$task_id" "$BUCKET_DONE"
      update_vikunja_task "$task_id" '{"done": true}'
      local page_names
      page_names=$(printf '%s, ' "${page_list[@]}" | sed 's/, $//')
      local wiki_urls
      wiki_urls=$(for p in "${page_list[@]}"; do echo "${SILVERBULLET_URL}/.fs/${p// /%20}.md"; done | tr '\n' ' ')
      add_task_comment "$task_id" "[COMPLETED] Wiki updated | Model: codex-exec/$CODEX_MODEL | Duration: ${duration_str} | Pages: ${page_names} | Agent: $AGENT_ID | URLs: ${wiki_urls}"
    fi
    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Wiki Task Done - #${task_id}" \
      "**${task_title}**\nPages updated: ${#page_list[@]} | Duration: ${duration_str}" \
      65280  # green
  else
    escalate_task_to_founder "$task_id" "$task_title" "Wiki task execution failed. Escalating to Needs Founder for manual pickup (Codex CLI or Claude Code CLI)."
  fi

  cleanup_worktree "$REPO_PATH" "$WORK_DIR"
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

  # Create an isolated worktree for this task (no shared state with other agents)
  local WORK_DIR=""
  WORK_DIR=$(setup_worktree "$REPO_PATH" "$branch_name") || true
  if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    log "ERROR: Failed to create worktree for task #$task_id"
    escalate_task_to_founder "$task_id" "$task_title" "Worktree creation failed for $REPO_NAME. Check disk space or stale worktrees."
    return
  fi

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
  selected_model=$(select_model "$task_title" "$task_description" | tail -1)
  log "Fallback model: $selected_model"

  # Safety net: if MODEL: founder leaked through, unclaim and abort
  if [[ "$selected_model" == "founder" ]]; then
    log "Task #$task_id has MODEL: founder — unclaiming and returning to To-Do"
    add_task_comment "$task_id" "[BLOCKED] MODEL: founder — reserved for manual work. Returning to To-Do. | Agent: $AGENT_ID"
    update_vikunja_task "$task_id" '{"percent_done": 0}'
    move_to_bucket "$task_id" "$BUCKET_TODO"
    cleanup_worktree "$REPO_PATH" "$WORK_DIR"
    return 0
  fi

  local execution_success=false

  # Build task history section for the prompt
  # Sanitize: strip references to other task IDs to prevent LLM confusion
  local history_section=""
  if [[ -n "$task_history" ]]; then
    # Remove "Task #NNN" references where NNN != current task_id
    local sanitized_history
    sanitized_history=$(echo "$task_history" | sed -E "s/Task #([0-9]+)/Task #$task_id/g") || true
    history_section="
## Previous Attempts (task history)
The following comments show what previous agents tried. Learn from any failures or blocked states:
$sanitized_history
"
  fi

  # --- Try Codex CLI first (has built-in file tools, best for coding) ---
  # Skip Codex if MODEL: override explicitly requests kimi or ollama
  if check_codex_available && [[ "$selected_model" == "codex" || -z "$(echo "$task_description" | sed 's/<[^>]*>//g' | grep -oiE 'MODEL:')" ]]; then
    log "Attempting Codex CLI execution (model: $CODEX_MODEL)..."
    model_used="codex-exec/$CODEX_MODEL"
    add_task_comment "$task_id" "[STARTED] Model: codex-exec/$CODEX_MODEL | Repo: $REPO_NAME | Agent: $AGENT_ID"

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
- If tests fail, fix them before committing
- Your commit message MUST reference Task #$task_id (not any other task number)
- Use commit message format: '[builder] Task #$task_id: <description>'
- ONLY create or modify files directly related to the task title
- Do NOT create views, components, or handlers for features not mentioned in the task
- If you need a dependency that doesn't exist yet, leave a TODO comment instead of implementing it"

    local codex_output
    local codex_start codex_end codex_exit
    codex_start=$(date +%s)
    if codex_output=$(_timeout "$CODEX_TIMEOUT" codex exec \
      --full-auto \
      --model "$CODEX_MODEL" \
      -C "$WORK_DIR" \
      "$codex_prompt" \
      2>&1); then
      codex_exit=$?
      codex_end=$(date +%s)
      log_codex_audit "$task_id" "initial" "$codex_exit" "$((codex_end - codex_start))"
      echo "$codex_output" >> "$LOG_FILE"
      log "Codex CLI execution completed (${codex_exit}, $((codex_end - codex_start))s)"

      # Safety net: if Codex modified files but didn't commit, auto-commit
      cd "$WORK_DIR"
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        log "Codex left uncommitted changes, auto-committing..."
        git add -A
        git commit -m "[builder] Task #$task_id: $task_title

Automated by Axinova Agent Fleet ($AGENT_ID, codex exec)
Model: codex-exec/$CODEX_MODEL" 2>>"$LOG_FILE" || true
      fi

      # Only mark success if Codex actually produced commits
      local codex_commit_count
      codex_commit_count=$(git log origin/main.."$branch_name" --oneline 2>/dev/null | wc -l | tr -d ' ') || codex_commit_count=0
      if [[ "$codex_commit_count" -gt 0 ]]; then
        execution_success=true
      else
        log "Codex exited successfully but produced no changes — escalating to Needs Founder"
        add_task_comment "$task_id" "[BLOCKED] Codex produced 0 changes (exit 0, no commits). Escalating to Needs Founder for manual pickup (Codex CLI or Claude Code CLI). | Agent: $AGENT_ID"
      fi
    else
      codex_exit=$?
      codex_end=$(date +%s)
      log_codex_audit "$task_id" "initial" "$codex_exit" "$((codex_end - codex_start))"
      echo "$codex_output" >> "$LOG_FILE"
      if [[ "$codex_exit" -eq 124 ]]; then
        log "Codex CLI TIMED OUT after ${CODEX_TIMEOUT}s — escalating to Needs Founder"
        add_task_comment "$task_id" "[TIMEOUT] Codex CLI timed out after ${CODEX_TIMEOUT}s. Escalating to Needs Founder for manual pickup (Codex CLI or Claude Code CLI). | Agent: $AGENT_ID"
      else
        log "Codex CLI failed (exit $codex_exit) — escalating to Needs Founder"
        add_task_comment "$task_id" "[BLOCKED] Codex CLI failed (exit $codex_exit). Escalating to Needs Founder for manual pickup (Codex CLI or Claude Code CLI). | Agent: $AGENT_ID"
      fi
      model_used="$selected_model"
    fi
  else
    log "Codex CLI not available — escalating to Needs Founder"
    add_task_comment "$task_id" "[BLOCKED] Codex CLI not available on this agent. Escalating to Needs Founder. | Agent: $AGENT_ID"
    escalate_task_to_founder "$task_id" "$task_title" "Codex CLI not available on agent $AGENT_ID. Needs manual pickup (Codex CLI or Claude Code CLI)."
    cleanup_worktree "$REPO_PATH" "$WORK_DIR"
    return 0
  fi

  # --- Kimi fallback removed (2026-03-13) ---
  # Kimi CLI had 5x more escalations than Codex and often exited with 0 changes.
  # If Codex fails, escalate directly to Needs Founder for manual Claude Code CLI pickup.

  # --- Ollama only runs if explicitly requested via MODEL: ollama ---
  if [[ "$execution_success" == "false" && "$model_used" == "ollama" ]]; then
    local diff_prompt
    diff_prompt=$(build_diff_prompt "$task_title" "$task_description" "$role_instructions" "$REPO_NAME" "$task_history")
    log "Calling Ollama (explicit MODEL: ollama override)..."
    local llm_output=""
    llm_output=$(call_ollama "$diff_prompt") || true

    if [[ -n "$llm_output" ]]; then
      log "LLM output length: ${#llm_output} chars (model: $model_used)"
      printf '%s\n' "$llm_output" >> "$LOG_FILE"

      local diff_content
      diff_content=$(extract_diff "$llm_output")

      if ! printf '%s' "$diff_content" | grep -q '^@@'; then
        log "ERROR: No valid hunk headers (@@) in extracted diff."
        llm_output=""
      elif ! printf '%s' "$diff_content" | grep -q '^--- '; then
        log "ERROR: No file headers (--- a/...) in extracted diff."
        llm_output=""
      fi

      if [[ -n "$llm_output" ]] && apply_diff "$diff_content" "$task_id"; then
        cd "$WORK_DIR"
        git add -A
        local commit_msg="[builder] Task #$task_id: $task_title

Automated by Axinova Agent Fleet ($AGENT_ID)
Model: $model_used"
        git commit -m "$commit_msg" 2>>"$LOG_FILE" && execution_success=true
      fi
    else
      log "ERROR: Ollama failed for task #$task_id"
    fi
  fi

  # --- Post-commit validation: task ID and scope checks ---
  local wrong_task_refs_detected=false
  local bad_task_refs=""

  if [[ "$execution_success" == "true" ]]; then
    cd "$WORK_DIR"

    # Fix 3: Validate commit messages reference the correct task ID
    # If wrong IDs found, auto-rewrite commits instead of blocking
    bad_task_refs=$(git log origin/main.."$branch_name" --oneline 2>/dev/null | grep -oE 'Task #[0-9]+' | grep -v "Task #$task_id" | sort -u) || true
    if [[ -n "$bad_task_refs" ]]; then
      log "WARN: Commits reference wrong task IDs: $bad_task_refs — auto-rewriting to Task #$task_id"
      # Rewrite all commit messages on the branch to use the correct task ID
      local rewrite_count
      rewrite_count=$(git log origin/main.."$branch_name" --oneline 2>/dev/null | wc -l | tr -d ' ') || rewrite_count=0
      if [[ "$rewrite_count" -gt 0 && "$rewrite_count" -le 10 ]]; then
        # Use filter-branch to fix task ID references in commit messages
        git filter-branch -f --msg-filter \
          "sed -E 's/Task #[0-9]+/Task #$task_id/g'" \
          origin/main.."$branch_name" 2>>"$LOG_FILE" || true
        # Verify the rewrite worked
        bad_task_refs=$(git log origin/main.."$branch_name" --oneline 2>/dev/null | grep -oE 'Task #[0-9]+' | grep -v "Task #$task_id" | sort -u) || true
        if [[ -n "$bad_task_refs" ]]; then
          wrong_task_refs_detected=true
          log "ERROR: Commit rewrite failed, still has wrong refs: $bad_task_refs"
          add_task_comment "$task_id" "[BLOCKED] Commits reference wrong task IDs: $bad_task_refs — rewrite failed. | Agent: $AGENT_ID"
        else
          log "Commit messages auto-fixed to reference Task #$task_id"
          add_task_comment "$task_id" "[FIX] Auto-corrected commit messages from $bad_task_refs to Task #$task_id | Agent: $AGENT_ID"
        fi
      else
        wrong_task_refs_detected=true
        log "ERROR: Too many commits ($rewrite_count) to safely rewrite"
        add_task_comment "$task_id" "[BLOCKED] Commits reference wrong task IDs: $bad_task_refs — too many commits to rewrite. | Agent: $AGENT_ID"
      fi
    fi

    # Fix 4: Validate changed files are in the expected repo directory
    local changed_files_outside_repo
    changed_files_outside_repo=$(git diff --name-only origin/main.."$branch_name" 2>/dev/null | grep -v "^" 2>/dev/null) || true
    # Check if any changed files suggest a different feature scope
    # Extract key feature words from task title (lowercase)
    local task_keywords
    task_keywords=$(echo "$task_title" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{4,}' | tr '\n' '|') || true
    if [[ -n "$task_keywords" ]]; then
      # Look for new files (added, not modified) that don't match any task keyword
      local new_files
      new_files=$(git diff --name-only --diff-filter=A origin/main.."$branch_name" 2>/dev/null) || true
      if [[ -n "$new_files" ]]; then
        # Check for views/components created for features NOT in the task title
        local suspicious_files=""
        while IFS= read -r file; do
          local file_lower
          file_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
          # Flag new View/Component files that don't match task keywords
          if echo "$file_lower" | grep -qE '(view|component|page|store)' 2>/dev/null; then
            local matches_task=false
            for kw in $(echo "$task_title" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{4,}'); do
              if echo "$file_lower" | grep -qi "$kw" 2>/dev/null; then
                matches_task=true
                break
              fi
            done
            if [[ "$matches_task" == "false" ]]; then
              suspicious_files="$suspicious_files $file"
            fi
          fi
        done <<< "$new_files"

        if [[ -n "${suspicious_files// /}" ]]; then
          log "WARNING: New files may be out of scope for task #$task_id: $suspicious_files"
          add_task_comment "$task_id" "[SCOPE WARNING] New files may not match task scope:${suspicious_files}. Task title: '$task_title'. Please verify during review. | Agent: $AGENT_ID"
        fi
      fi
    fi
  fi

  # --- Local CI: run tests before creating PR ---
  local ci_passed=true
  if [[ "$execution_success" == "true" ]]; then
    log "Running local CI checks..."
    add_task_comment "$task_id" "[CI] Running local tests..."
    cd "$WORK_DIR"

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
      if [[ "$model_used" == "codex-cli/"* ]] && check_codex_available; then
        local cifix_start cifix_end cifix_exit
        cifix_start=$(date +%s)
        fix_output=$(_timeout "$CODEX_TIMEOUT" codex exec --full-auto -C "$WORK_DIR" \
          "Fix the following test failures. Do NOT introduce new features, only fix the failing tests.

$ci_error" 2>&1) || true
        cifix_exit=$?
        cifix_end=$(date +%s)
        log_codex_audit "$task_id" "ci-fix" "$cifix_exit" "$((cifix_end - cifix_start))"
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
        add_task_comment "$task_id" "[CI-FAILED] Tests still failing after fix attempt — will not auto-retry on PR"
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
  has_commits=$(git -C "$WORK_DIR" log "origin/main..$branch_name" --oneline 2>/dev/null | wc -l | tr -d ' ')

  # Fix #5: Don't create PRs when local CI failed — escalate directly instead of
  # creating a broken PR that triggers the PR health check loop
  if [[ "$has_commits" -gt 0 && "$ci_passed" == "false" ]]; then
    log "Task #$task_id: $has_commits commit(s) but local CI failed — skipping PR, escalating"
    add_task_comment "$task_id" "[BLOCKED] Code changes made but local CI failed. Escalating instead of creating a broken PR."
    escalate_task_to_founder "$task_id" "$task_title" "Agent produced code changes but local CI fails. Branch: \`$branch_name\` in $REPO_NAME. Model: $model_used, Duration: $duration_str."
    cleanup_worktree "$REPO_PATH" "$WORK_DIR"
    return
  fi

  if [[ "$has_commits" -gt 0 && "$wrong_task_refs_detected" == "true" ]]; then
    log "Task #$task_id: commit/task mismatch detected ($bad_task_refs) — skipping PR, escalating"
    add_task_comment "$task_id" "[NEEDS FOUNDER] Commit/task mismatch detected ($bad_task_refs). Branch: \`$branch_name\`. PR not created."
    escalate_task_to_founder "$task_id" "$task_title" "Commit messages reference $bad_task_refs instead of Task #$task_id. Branch: \`$branch_name\` in $REPO_NAME. PR creation blocked to prevent cross-task merge."
    cleanup_worktree "$REPO_PATH" "$WORK_DIR"
    return
  fi

  if [[ "$has_commits" -gt 0 ]]; then
    log "Task #$task_id: $has_commits commit(s) made, pushing and creating PR"

    git -C "$WORK_DIR" push -u origin "$branch_name" 2>>"$LOG_FILE"

    local pr_url
    pr_url=$(cd "$WORK_DIR" && gh pr create \
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
- Local CI: PASSED

## Changes
$(git -C "$WORK_DIR" log origin/main..$branch_name --pretty=format:'- %s' 2>/dev/null)

---
Automated by Axinova Agent Fleet
PRBODY
)" \
      --base main \
      2>>"$LOG_FILE") || true

    if [[ -n "$pr_url" ]]; then
      log "PR created: $pr_url"
      # Move to In Review (not Done — founder reviews the PR first)
      move_to_bucket "$task_id" "$BUCKET_IN_REVIEW"
      # Append PR result to description using jq to safely handle HTML content
      # FIX: Do NOT use echo -e (corrupts HTML backslash sequences).
      # Instead, use jq to read existing description and append the result note.
      local pr_note="PR: $pr_url | Model: $model_used | CI: PASSED"
      local existing_task_json
      existing_task_json=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null) || true
      local existing_desc
      existing_desc=$(echo "$existing_task_json" | jq -r '.description // ""' 2>/dev/null || echo "")
      # Use jq to safely concatenate description + result note (no echo -e, no double-escaping)
      local merged_payload
      merged_payload=$(jq -n \
        --arg desc "$existing_desc" \
        --arg note "$pr_note" \
        '{percent_done: 0.8, description: ($desc + "\n\n--- Result ---\n" + $note)}')
      vikunja_api POST "/tasks/${task_id}" "$merged_payload" >>"$LOG_FILE" 2>&1 || true
      add_task_comment "$task_id" "[IN REVIEW] PR: $pr_url | Model: $model_used | Duration: $duration_str | Commits: $has_commits | CI: PASSED"

      # Notify Discord #agent-prs with rich embed
      notify_discord_rich "${DISCORD_WEBHOOK_PRS:-}" \
        "PR Created - Task #$task_id" \
        "**$task_title**\n$pr_url" \
        65280 \
        "Model" "$model_used" \
        "Duration" "$duration_str" \
        "Repo" "$REPO_NAME" \
        "CI" "PASSED"
    else
      log "WARNING: Failed to create PR for task #$task_id"
      escalate_task_to_founder "$task_id" "$task_title" "PR creation failed — commits exist on branch \`$branch_name\` but \`gh pr create\` failed. Repo: $REPO_NAME"
    fi
  else
    log "Task #$task_id: No commits made, escalating to founder"
    escalate_task_to_founder "$task_id" "$task_title" "Agent produced no code changes. Model: $model_used, Duration: $duration_str. May need clearer instructions."
  fi

  # Clean up the worktree (branch stays on remote after push)
  cleanup_worktree "$REPO_PATH" "$WORK_DIR"
}

# --- PR Retry Thresholds ---
MAX_REVIEW_ATTEMPTS=3      # Max times agent will try to address review comments per PR
MAX_CONFLICT_ATTEMPTS=2    # Max times agent will try to resolve conflicts per PR
MAX_CI_FIX_ATTEMPTS=1      # Max times agent will try to fix CI failures per PR (reduced: local fix already tried in execute_task)

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
  task_id_from_pr=$(echo "$pr_branch" | sed -n 's/.*task-\([0-9][0-9]*\).*/\1/p' | head -1 || echo "")
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
  # Scan all repos in workspace for this agent's open PRs
  local repos
  repos=$(find "$WORKSPACE" -maxdepth 1 -name "axinova-*" -type d 2>/dev/null)
  [[ -z "$repos" ]] && return 0

  for _pr_repo_dir in $repos; do
    [[ ! -d "$_pr_repo_dir/.git" ]] && continue
    # Set REPO_PATH for sub-functions (escalate_to_human, etc.)
    REPO_PATH="$_pr_repo_dir"

  # List open PRs by this agent — gh --head requires exact branch, so filter with jq
  local all_prs prs
  all_prs=$(cd "$REPO_PATH" && gh pr list --state open \
    --json number,title,headRefName,url,mergeable \
    2>/dev/null) || continue
  prs=$(echo "$all_prs" | jq --arg aid "$AGENT_ID" \
    '[.[] | select(.headRefName | startswith("agent/"+$aid+"/"))]' 2>/dev/null) || continue

  local pr_count
  pr_count=$(echo "$prs" | jq 'length' 2>/dev/null || echo "0")
  [[ "$pr_count" == "0" ]] && continue

  log "Monitoring $pr_count open PR(s) in $(basename "$REPO_PATH")..."

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
  done  # end repo loop
}

# --- Fix CI Failures ---
_fix_ci_failure() {
  local pr_number="$1" pr_title="$2" pr_branch="$3" pr_url="$4" counter_file="$5"

  local WORK_DIR=""
  WORK_DIR=$(setup_worktree_existing "$REPO_PATH" "$pr_branch") || { log "Failed to create worktree for PR #$pr_number CI fix"; return; }
  cd "$WORK_DIR"

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
    local prci_start prci_end prci_exit
    prci_start=$(date +%s)
    if _timeout "$CODEX_TIMEOUT" codex exec --full-auto -C "$WORK_DIR" "$fix_prompt" >>"$LOG_FILE" 2>&1; then
      prci_exit=0
      prci_end=$(date +%s)
      log_codex_audit "" "pr-ci-fix" "0" "$((prci_end - prci_start))" "$pr_number"
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git add -A
        git commit -m "[$ROLE] Fix CI failure on PR #$pr_number" 2>>"$LOG_FILE" || true
      fi
      fix_success=true
    else
      prci_exit=$?
      prci_end=$(date +%s)
      log_codex_audit "" "pr-ci-fix" "$prci_exit" "$((prci_end - prci_start))" "$pr_number"
      log "Codex CI fix failed (exit $prci_exit, $((prci_end - prci_start))s)"
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

    if [[ "$ci_ok" == "true" ]]; then
      git push origin "$pr_branch" 2>>"$LOG_FILE" || true

      gh pr comment "$pr_number" --body "Pushed CI fix ($(git rev-parse --short HEAD)). Local CI: PASSED" \
        >>"$LOG_FILE" 2>&1 || true

      log "PR #$pr_number: CI fix pushed (local CI passed)"
      notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
        "CI Fix Pushed - PR #$pr_number" \
        "**$pr_title**\nCI fix pushed (local CI passed).\n$pr_url" \
        5814783  # blue
    else
      log "PR #$pr_number: local CI still failing after fix — NOT pushing broken code"
      gh pr comment "$pr_number" --body "CI fix attempted but local CI still FAILS. Not pushing. Escalating to founder." \
        >>"$LOG_FILE" 2>&1 || true

      # Extract task ID from PR title if possible, escalate
      local pr_task_id
      pr_task_id=$(echo "$pr_title" | grep -oE 'Task #[0-9]+' | grep -oE '[0-9]+' | head -1) || true
      if [[ -n "$pr_task_id" ]]; then
        escalate_task_to_founder "$pr_task_id" "$pr_title" "CI fix attempted on PR #$pr_number but local CI still fails. Branch: \`$pr_branch\`. NOT pushed to avoid merging broken code."
      fi

      notify_discord "${DISCORD_WEBHOOK_ALERTS:-}" \
        "CI Fix FAILED - PR #$pr_number" \
        "**$pr_title**\nLocal CI still failing after fix attempt. Not pushed.\n$pr_url" \
        16711680  # red
    fi
  else
    log "PR #$pr_number: CI fix attempt failed"
  fi

  cleanup_worktree "$REPO_PATH" "$WORK_DIR"
}

# --- Resolve Merge Conflicts ---
_resolve_conflicts() {
  local pr_number="$1" pr_title="$2" pr_branch="$3" pr_url="$4" counter_file="$5"

  local WORK_DIR=""
  WORK_DIR=$(setup_worktree_existing "$REPO_PATH" "$pr_branch") || { log "Failed to create worktree for PR #$pr_number conflict resolution"; return; }
  cd "$WORK_DIR"

  if git rebase origin/main 2>>"$LOG_FILE"; then
    git push --force-with-lease origin "$pr_branch" 2>>"$LOG_FILE" || {
      log "PR #$pr_number: rebase succeeded but push failed"
      increment_counter "$counter_file" > /dev/null
      cleanup_worktree "$REPO_PATH" "$WORK_DIR"
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

    # Try cherry-pick recreation: get commit list, then recreate branch from origin/main
    local pr_commits
    pr_commits=$(git log --reverse --format='%H' "origin/main..ORIG_HEAD" 2>/dev/null)

    if [[ -n "$pr_commits" ]]; then
      # Remove the worktree so we can delete and recreate the branch
      cleanup_worktree "$REPO_PATH" "$WORK_DIR"
      git -C "$REPO_PATH" branch -D "$pr_branch" 2>>"$LOG_FILE" || true

      # Create a fresh worktree from origin/main with the same branch name
      WORK_DIR=$(setup_worktree "$REPO_PATH" "$pr_branch") || {
        log "PR #$pr_number: failed to recreate branch for cherry-pick"
        return
      }
      cd "$WORK_DIR"

      local cherry_success=true
      while IFS= read -r commit_sha; do
        if ! git cherry-pick "$commit_sha" 2>>"$LOG_FILE"; then
          git cherry-pick --abort 2>>"$LOG_FILE" || true
          cherry_success=false
          break
        fi
      done <<< "$pr_commits"

      if [[ "$cherry_success" == "true" ]]; then
        git push --force-with-lease origin "$pr_branch" 2>>"$LOG_FILE" || { cleanup_worktree "$REPO_PATH" "$WORK_DIR"; return; }
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

  cleanup_worktree "$REPO_PATH" "$WORK_DIR"
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

  local WORK_DIR=""
  WORK_DIR=$(setup_worktree_existing "$REPO_PATH" "$pr_branch") || { log "Failed to create worktree for PR #$pr_number review fix"; return; }
  cd "$WORK_DIR"

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
    local rev_start rev_end rev_exit
    rev_start=$(date +%s)
    if _timeout "$CODEX_TIMEOUT" codex exec --full-auto -C "$WORK_DIR" "$review_prompt" >>"$LOG_FILE" 2>&1; then
      rev_exit=0
      rev_end=$(date +%s)
      log_codex_audit "" "review-fix" "0" "$((rev_end - rev_start))" "$pr_number"
      if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git add -A
        git commit -m "[$ROLE] Address review feedback on PR #$pr_number

Feedback: ${comment_body:0:100}" 2>>"$LOG_FILE" || true
      fi
      review_success=true
    else
      rev_exit=$?
      rev_end=$(date +%s)
      log_codex_audit "" "review-fix" "$rev_exit" "$((rev_end - rev_start))" "$pr_number"
      log "Codex review fix failed (exit $rev_exit, $((rev_end - rev_start))s)"
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
  cleanup_worktree "$REPO_PATH" "$WORK_DIR"
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
    TASK_PRIORITY=$(echo "$TASK_JSON" | jq -r '.priority // 0' 2>/dev/null || echo "0")
    # Cache the project_id for this task so move_to_bucket can skip the GET
    ACTIVE_TASK_PROJECT_ID=$(echo "$TASK_JSON" | jq -r '.project_id // 0' 2>/dev/null || echo "0")

    log "Found task #$TASK_ID: $TASK_TITLE"

    # Step 1: Fast pre-claim validity check (no LLM calls, no comments).
    # Enrichment happens AFTER claim to prevent all agents spamming [ENRICHING] simultaneously.
    if ! check_task_validity "$TASK_ID" "$TASK_TITLE" "$TASK_DESC"; then
      log "Task #$TASK_ID skipped — failed validity check (no repo name or bad wiki format)"
      sleep "$POLL_INTERVAL"
      continue
    fi

    # Step 2: Claim with jitter + re-verify (only one agent wins)
    if ! claim_task "$TASK_ID"; then
      log "Task #$TASK_ID claimed by another builder — back to polling"
      sleep "$POLL_INTERVAL"
      continue
    fi

    notify_discord "${DISCORD_WEBHOOK_LOGS:-}" \
      "Task Claimed - #$TASK_ID" \
      "**$TASK_TITLE**\nAgent: \`$AGENT_ID\`" \
      5814783  # blue

    # Step 3: Enrich description AFTER claiming (only the winning agent does this)
    if [[ -z "$TASK_DESC" || ${#TASK_DESC} -lt 20 ]]; then
      _enrich_repo=$(detect_repo_path "$TASK_TITLE")
      if [[ -z "$_enrich_repo" ]]; then
        add_task_comment "$TASK_ID" "[BLOCKED] Task description is empty and no repo found for auto-enrichment. Resetting to unclaimed."
        update_vikunja_task "$TASK_ID" '{"percent_done": 0}'
        move_to_bucket "$TASK_ID" "$BUCKET_TODO"
        sleep "$POLL_INTERVAL"
        continue
      fi
      _enriched=""
      if _enriched=$(auto_enrich_description "$TASK_ID" "$TASK_TITLE" "$_enrich_repo"); then
        TASK_DESC="$_enriched"
        log "Task #$TASK_ID: using auto-enriched description (${#TASK_DESC} chars)"
      else
        add_task_comment "$TASK_ID" "[BLOCKED] Auto-enrichment failed — please add a description manually. Resetting to unclaimed."
        update_vikunja_task "$TASK_ID" '{"percent_done": 0}'
        move_to_bucket "$TASK_ID" "$BUCKET_TODO"
        sleep "$POLL_INTERVAL"
        continue
      fi
    fi

    # Complexity heuristic: auto-escalate complex tasks to founder
    # Priority ≥4 (set at design time) bypasses keyword scoring entirely
    _complexity_score=0
    _complexity_score=$(estimate_complexity "$TASK_TITLE" "$TASK_DESC" "$TASK_PRIORITY") || _complexity_score=0
    log "Task #$TASK_ID complexity score: $_complexity_score (priority: $TASK_PRIORITY)"
    if [[ "$_complexity_score" -ge 4 ]]; then
      log "Task #$TASK_ID: complexity score $_complexity_score >= 4 — escalating to founder"
      escalate_task_to_founder "$TASK_ID" "$TASK_TITLE" "Auto-escalated: complexity score $_complexity_score (priority: $TASK_PRIORITY, threshold: 4). Task needs manual pickup (Codex CLI or Claude Code CLI)."
      sleep "$POLL_INTERVAL"
      continue
    fi

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

  # Prune stale worktrees every 10 loops (~20 min). Handles crash/kill scenarios
  # where cleanup_worktree never ran. Only one builder per machine does this.
  if [[ "$AGENT_ID" == "builder-1" || "$AGENT_ID" == "builder-11" ]] && (( _loop_count % 10 == 0 )); then
    if [[ -d "$WORKTREE_BASE" ]]; then
      _stale_count=0
      for _wt_repo_dir in "$WORKTREE_BASE"/*/; do
        [ -d "$_wt_repo_dir" ] || continue
        _base_repo="$WORKSPACE/$(basename "$_wt_repo_dir")"
        [ -d "$_base_repo/.git" ] || continue
        # git worktree prune removes entries whose directories no longer exist
        git -C "$_base_repo" worktree prune 2>>"$LOG_FILE" || true
        # Remove worktree dirs that have been sitting idle for >2 hours (stale from crashes)
        for _wt_dir in "$_wt_repo_dir"*/; do
          [ -d "$_wt_dir" ] || continue
          # Check if the worktree dir was last modified >2 hours ago
          _age_min=$(( ( $(date +%s) - $(stat -f%m "$_wt_dir" 2>/dev/null || echo "0") ) / 60 ))
          if [[ "$_age_min" -gt 120 ]]; then
            log "Pruning stale worktree (${_age_min}min old): $_wt_dir"
            git -C "$_base_repo" worktree remove --force "$_wt_dir" 2>>"$LOG_FILE" || rm -rf "$_wt_dir"
            _stale_count=$((_stale_count + 1))
          fi
        done
      done
      [[ "$_stale_count" -gt 0 ]] && log "Pruned $_stale_count stale worktree(s)"
    fi
  fi

  # Add jitter (0-15s) to prevent all builders polling at the exact same moment
  _jitter=$((RANDOM % 16))
  sleep $((POLL_INTERVAL + _jitter))
done
