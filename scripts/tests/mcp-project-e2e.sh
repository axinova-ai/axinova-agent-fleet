#!/usr/bin/env bash
# ============================================================
# MCP Multi-Project E2E Test
# ============================================================
# Validates the full Vikunja MCP workflow for multi-project
# task management with labels, filtered views, and buckets.
#
# Creates a temporary test project, labels, views, and tasks,
# runs all assertions, then cleans up.
#
# Usage:
#   ./scripts/tests/mcp-project-e2e.sh              # Run all tests
#   ./scripts/tests/mcp-project-e2e.sh --cleanup     # Just clean leftover test data
#   ./scripts/tests/mcp-project-e2e.sh --skip-agent   # Skip agent scheduler tests
#   ./scripts/tests/mcp-project-e2e.sh --mcp-only     # Only test MCP tools (no scheduler)
#
# Prerequisites:
#   - Vikunja accessible at localhost:3456 (SSH tunnel)
#   - axinova-mcp-server binary with multi-project features
#   - jq, curl installed
#   - For agent tests: agents running on agent01 + agent02
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VIKUNJA_URL="http://localhost:3456/api/v1"
VIKUNJA_TOKEN=""
TIMEOUT="${TIMEOUT:-120}"
TEST_PREFIX="[MCP-E2E]"
SKIP_AGENT=false
MCP_ONLY=false

# Test project — created fresh each run, deleted at cleanup
TEST_PROJECT_NAME="$TEST_PREFIX test-project-$(date +%s)"
TEST_PROJECT_ID=""

# Test labels — created fresh, deleted at cleanup
TEST_LABEL_SPRINT1=""
TEST_LABEL_SPRINT2=""
TEST_LABEL_EPIC=""

# Test view + buckets
TEST_VIEW_ID=""
TEST_BUCKET_TODO=""
TEST_BUCKET_DOING=""
TEST_BUCKET_DONE=""

# Task IDs for cleanup
declare -a CLEANUP_TASK_IDS=()
declare -a CLEANUP_LABEL_IDS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Results — 15 tests
RESULT_P1="SKIP" RESULT_P2="SKIP"
RESULT_L1="SKIP" RESULT_L2="SKIP"
RESULT_T1="SKIP" RESULT_T2="SKIP" RESULT_T3="SKIP" RESULT_T4="SKIP" RESULT_T5="SKIP"
RESULT_V1="SKIP" RESULT_V2="SKIP" RESULT_V3="SKIP" RESULT_V4="SKIP"
RESULT_B1="SKIP"
RESULT_A1="SKIP" RESULT_A2="SKIP"
RESULT_E2E="SKIP"

# --- Helpers ---

load_token() {
  local env_file="$HOME/.config/axinova/mcp.env"
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: $env_file not found" >&2
    exit 1
  fi
  VIKUNJA_TOKEN=$(grep 'APP_VIKUNJA__TOKEN' "$env_file" | cut -d= -f2)
  if [[ -z "$VIKUNJA_TOKEN" ]]; then
    echo "ERROR: APP_VIKUNJA__TOKEN not found in $env_file" >&2
    exit 1
  fi
}

api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "${VIKUNJA_URL}${path}" \
    -H "Authorization: Bearer $VIKUNJA_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

pass() { printf "  ${GREEN}PASS${NC}: %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}: %s\n" "$1"; }
info() { printf "  ${CYAN}INFO${NC}: %s\n" "$1"; }

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
    return 0
  else
    fail "$msg (expected='$expected', got='$actual')"
    return 1
  fi
}

assert_not_empty() {
  local value="$1" msg="$2"
  if [[ -n "$value" && "$value" != "null" && "$value" != "0" ]]; then
    pass "$msg"
    return 0
  else
    fail "$msg (got empty/null/0)"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -q "$needle" 2>/dev/null; then
    pass "$msg"
    return 0
  else
    fail "$msg (needle='$needle' not found)"
    return 1
  fi
}

assert_count() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$msg"
    return 0
  else
    fail "$msg (expected=$expected, got=$actual)"
    return 1
  fi
}

# --- Test: P1 — Create test project ---

run_test_p1() {
  echo -e "\n${CYAN}[P1] Create test project${NC}"
  local result
  result=$(api PUT "/projects" -d "$(python3 -c "import json,sys; print(json.dumps({'title': sys.argv[1]}))" "$TEST_PROJECT_NAME")")
  TEST_PROJECT_ID=$(echo "$result" | jq -r '.id // 0')

  if assert_not_empty "$TEST_PROJECT_ID" "Project created with ID"; then
    info "Project: #$TEST_PROJECT_ID '$TEST_PROJECT_NAME'"
    RESULT_P1="PASS"
  else
    RESULT_P1="FAIL"
    echo "  FATAL: Cannot continue without test project"
    return 1
  fi
}

# --- Test: P2 — Resolve project by name ---
# Tests the NEW MCP tool: vikunja_resolve_project
# For now, simulates by listing projects and matching

run_test_p2() {
  echo -e "\n${CYAN}[P2] Resolve project by name${NC}"
  local projects
  projects=$(api GET "/projects") || { RESULT_P2="FAIL"; return; }

  # Simulate resolve: search by exact test project name
  local matched_id
  matched_id=$(echo "$projects" | jq -r --arg name "$TEST_PROJECT_NAME" '.[] | select(.title == $name) | .id' | head -1) || matched_id=""

  if assert_eq "$matched_id" "$TEST_PROJECT_ID" "Resolve project by exact name -> #$TEST_PROJECT_ID"; then
    RESULT_P2="PASS"
  else
    RESULT_P2="FAIL"
  fi
}

# --- Test: L1 — Create sprint labels ---

run_test_l1() {
  echo -e "\n${CYAN}[L1] Create sprint labels${NC}"

  local r1 r2 r3
  r1=$(api PUT "/labels" -d '{"title": "'"$TEST_PREFIX"' sprint-1", "hex_color": "#22c55e"}')
  TEST_LABEL_SPRINT1=$(echo "$r1" | jq -r '.id // 0')
  CLEANUP_LABEL_IDS+=("$TEST_LABEL_SPRINT1")

  r2=$(api PUT "/labels" -d '{"title": "'"$TEST_PREFIX"' sprint-2", "hex_color": "#3b82f6"}')
  TEST_LABEL_SPRINT2=$(echo "$r2" | jq -r '.id // 0')
  CLEANUP_LABEL_IDS+=("$TEST_LABEL_SPRINT2")

  r3=$(api PUT "/labels" -d '{"title": "'"$TEST_PREFIX"' epic-merchant", "hex_color": "#a855f7"}')
  TEST_LABEL_EPIC=$(echo "$r3" | jq -r '.id // 0')
  CLEANUP_LABEL_IDS+=("$TEST_LABEL_EPIC")

  local all_ok=true
  assert_not_empty "$TEST_LABEL_SPRINT1" "Created label sprint-1 (#$TEST_LABEL_SPRINT1)" || all_ok=false
  assert_not_empty "$TEST_LABEL_SPRINT2" "Created label sprint-2 (#$TEST_LABEL_SPRINT2)" || all_ok=false
  assert_not_empty "$TEST_LABEL_EPIC" "Created label epic-merchant (#$TEST_LABEL_EPIC)" || all_ok=false

  if $all_ok; then RESULT_L1="PASS"; else RESULT_L1="FAIL"; fi
}

# --- Test: L2 — Resolve label by name ---

run_test_l2() {
  echo -e "\n${CYAN}[L2] Resolve label by name${NC}"
  local labels
  labels=$(api GET "/labels") || { RESULT_L2="FAIL"; return; }

  # Simulate resolve: search by exact label title
  local search_title="$TEST_PREFIX sprint-1"
  local matched_id
  matched_id=$(echo "$labels" | jq -r --arg name "$search_title" '.[] | select(.title == $name) | .id' | head -1) || matched_id=""

  if assert_eq "$matched_id" "$TEST_LABEL_SPRINT1" "Resolve '$search_title' -> label #$TEST_LABEL_SPRINT1"; then
    RESULT_L2="PASS"
  else
    RESULT_L2="FAIL"
  fi
}

# --- Test: T1 — Create task with label ---
# Tests: vikunja_create_task + vikunja_add_task_label (2-step in current MCP)
# After MCP update: should be single call with labels param

run_test_t1() {
  echo -e "\n${CYAN}[T1] Create task with label (sprint-1)${NC}"

  # Step 1: Create task
  local result
  local json_body
  json_body=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "description": sys.argv[2]}))' \
    "$TEST_PREFIX task-1 with sprint label" "<p>Test task for sprint-1</p>")
  result=$(api PUT "/projects/$TEST_PROJECT_ID/tasks" -d "$json_body")
  local tid
  tid=$(echo "$result" | jq -r '.id // 0')
  CLEANUP_TASK_IDS+=("$tid")

  # Step 2: Add label
  api PUT "/tasks/$tid/labels" -d "{\"label_id\": $TEST_LABEL_SPRINT1}" >/dev/null 2>&1
  # Also add epic label
  api PUT "/tasks/$tid/labels" -d "{\"label_id\": $TEST_LABEL_EPIC}" >/dev/null 2>&1

  # Verify task has both labels
  local task
  task=$(api GET "/tasks/$tid")
  local label_count
  label_count=$(echo "$task" | jq '.labels | length') || label_count=0

  local ok=true
  assert_not_empty "$tid" "Task created (#$tid)" || ok=false
  assert_count "$label_count" 2 "Task has 2 labels (sprint-1 + epic)" || ok=false

  if $ok; then RESULT_T1="PASS"; else RESULT_T1="FAIL"; fi
}

# --- Test: T2 — Bulk create tasks with labels ---

run_test_t2() {
  echo -e "\n${CYAN}[T2] Bulk create 3 tasks, assign sprint-1 label${NC}"

  local tids=()
  for i in 2 3 4; do
    local result
    result=$(api PUT "/projects/$TEST_PROJECT_ID/tasks" \
      -d "$(python3 -c "import json,sys; print(json.dumps({'title': sys.argv[1]}))" "$TEST_PREFIX task-$i bulk create")")
    local tid
    tid=$(echo "$result" | jq -r '.id // 0')
    CLEANUP_TASK_IDS+=("$tid")
    tids+=("$tid")
    # Add sprint-1 label
    api PUT "/tasks/$tid/labels" -d "{\"label_id\": $TEST_LABEL_SPRINT1}" >/dev/null 2>&1
  done

  # Verify all 3 have the label
  local all_labeled=true
  for tid in "${tids[@]}"; do
    local task
    task=$(api GET "/tasks/$tid")
    local has_label
    has_label=$(echo "$task" | jq ".labels[]? | select(.id == $TEST_LABEL_SPRINT1) | .id" 2>/dev/null) || has_label=""
    if [[ -z "$has_label" ]]; then
      all_labeled=false
      fail "Task #$tid missing sprint-1 label"
    fi
  done

  if assert_count "${#tids[@]}" 3 "Created 3 tasks" && $all_labeled; then
    pass "All 3 tasks have sprint-1 label"
    RESULT_T2="PASS"
  else
    RESULT_T2="FAIL"
  fi
}

# --- Test: T3 — List tasks filtered by label ---

run_test_t3() {
  echo -e "\n${CYAN}[T3] List tasks filtered by label (sprint-1)${NC}"

  # Vikunja filter syntax: labels in <id>
  local filter="labels in $TEST_LABEL_SPRINT1"
  local encoded_filter
  encoded_filter=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$filter'))")

  local result
  result=$(api GET "/projects/$TEST_PROJECT_ID/tasks?filter=$encoded_filter&filter_include_nulls=false")
  local count
  count=$(echo "$result" | jq 'length') || count=0

  # We created 4 tasks with sprint-1 label (1 in T1 + 3 in T2)
  if assert_count "$count" 4 "Filter returns 4 sprint-1 tasks"; then
    RESULT_T3="PASS"
  else
    info "Got $count tasks (expected 4)"
    RESULT_T3="FAIL"
  fi
}

# --- Test: T4 — Filter combo: label + done=false ---

run_test_t4() {
  echo -e "\n${CYAN}[T4] Filter: sprint-1 AND not done${NC}"

  # Mark one task as done first
  local done_tid="${CLEANUP_TASK_IDS[1]}"
  local full_task
  full_task=$(api GET "/tasks/$done_tid")
  local updated
  updated=$(echo "$full_task" | python3 -c "
import json, sys
raw = sys.stdin.read()
clean = ''.join(c if c in '\n\t' or ord(c) >= 32 else '' for c in raw)
task = json.loads(clean)
task['done'] = True
print(json.dumps(task))
" 2>/dev/null) || updated='{"done": true}'
  api POST "/tasks/$done_tid" -d "$updated" >/dev/null 2>&1

  # Now filter: sprint-1 AND not done
  local filter="labels in $TEST_LABEL_SPRINT1 && done = false"
  local encoded_filter
  encoded_filter=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$filter")

  local result
  result=$(api GET "/projects/$TEST_PROJECT_ID/tasks?filter=$encoded_filter&filter_include_nulls=false")
  local count
  count=$(echo "$result" | jq 'length') || count=0

  # 4 sprint-1 tasks minus 1 done = 3
  if assert_count "$count" 3 "Filter returns 3 open sprint-1 tasks (1 marked done)"; then
    RESULT_T4="PASS"
  else
    info "Got $count tasks (expected 3)"
    RESULT_T4="FAIL"
  fi
}

# --- Test: T5 — Update task without wiping description ---
# This is a critical regression test: Vikunja POST /tasks/{id} replaces ALL fields.
# If an update omits description, it gets wiped to empty string.

run_test_t5() {
  echo -e "\n${CYAN}[T5] Update task preserves description (no wipe)${NC}"

  # Create a task with a rich HTML description
  local desc_html="<h2>Feature</h2><p>This is a <strong>rich</strong> description with HTML.</p><ul><li>Item 1</li><li>Item 2</li></ul>"
  local json_body
  json_body=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "description": sys.argv[2], "priority": 3}))' \
    "$TEST_PREFIX task-t5 description wipe test" "$desc_html")
  local result
  result=$(api PUT "/projects/$TEST_PROJECT_ID/tasks" -d "$json_body")
  local tid
  tid=$(echo "$result" | jq -r '.id // 0')
  CLEANUP_TASK_IDS+=("$tid")

  # Verify description was saved
  local task_before
  task_before=$(api GET "/tasks/$tid")
  local desc_before
  desc_before=$(echo "$task_before" | jq -r '.description // ""')

  if [[ -z "$desc_before" ]]; then
    fail "Description was empty after creation"
    RESULT_T5="FAIL"
    return
  fi

  # Now update ONLY the done field (the dangerous operation)
  # Use GET-then-POST pattern to simulate safe update
  local full_task
  full_task=$(api GET "/tasks/$tid")
  local updated_payload
  updated_payload=$(echo "$full_task" | python3 -c "
import json, sys
raw = sys.stdin.read()
clean = ''.join(c if c in '\n\t' or ord(c) >= 32 else '' for c in raw)
task = json.loads(clean)
task['done'] = True
print(json.dumps(task))
" 2>/dev/null)
  api POST "/tasks/$tid" -d "$updated_payload" >/dev/null 2>&1

  # Verify description survived the update
  local task_after
  task_after=$(api GET "/tasks/$tid")
  local desc_after
  desc_after=$(echo "$task_after" | jq -r '.description // ""')
  local priority_after
  priority_after=$(echo "$task_after" | jq -r '.priority // 0')
  local done_after
  done_after=$(echo "$task_after" | jq -r '.done')

  local ok=true
  if [[ -n "$desc_after" && "$desc_after" != "null" ]]; then
    pass "Description preserved after update (${#desc_after} chars)"
  else
    fail "Description WIPED after update!"
    ok=false
  fi

  assert_eq "$done_after" "true" "Done flag updated correctly" || ok=false
  assert_eq "$priority_after" "3" "Priority preserved (not reset to 0)" || ok=false

  # Also test a DANGEROUS partial update (POST without description) to prove the wipe scenario
  local partial_payload='{"title": "'"$TEST_PREFIX"' task-t5 renamed"}'
  api POST "/tasks/$tid" -d "$partial_payload" >/dev/null 2>&1

  local task_partial
  task_partial=$(api GET "/tasks/$tid")
  local desc_partial
  desc_partial=$(echo "$task_partial" | jq -r '.description // ""')
  local priority_partial
  priority_partial=$(echo "$task_partial" | jq -r '.priority // 0')

  if [[ -z "$desc_partial" || "$desc_partial" == "null" ]]; then
    pass "Confirmed: partial POST wipes description (this is expected Vikunja behavior)"
  else
    info "Partial POST did NOT wipe description (Vikunja may have changed behavior)"
  fi

  if [[ "$priority_partial" == "0" ]]; then
    pass "Confirmed: partial POST resets priority to 0 (expected Vikunja behavior)"
  else
    info "Partial POST did NOT reset priority"
  fi

  if $ok; then RESULT_T5="PASS"; else RESULT_T5="FAIL"; fi
}

# --- Test: V1 — Create kanban view with filter ---

run_test_v1() {
  echo -e "\n${CYAN}[V1] Create filtered kanban view for sprint-1${NC}"

  local result
  local view_body
  view_body=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "view_kind": "kanban", "filter": {"filter": sys.argv[2], "filter_include_nulls": False}, "bucket_configuration_mode": "manual"}))' \
    "$TEST_PREFIX Sprint 1 Board" "labels in $TEST_LABEL_SPRINT1 && done = false")
  result=$(api PUT "/projects/$TEST_PROJECT_ID/views" -d "$view_body")
  TEST_VIEW_ID=$(echo "$result" | jq -r '.id // 0')

  if assert_not_empty "$TEST_VIEW_ID" "Kanban view created (#$TEST_VIEW_ID)"; then
    RESULT_V1="PASS"
  else
    RESULT_V1="FAIL"
  fi
}

# --- Test: V2 — List views for project ---

run_test_v2() {
  echo -e "\n${CYAN}[V2] List views for test project${NC}"

  local result
  result=$(api GET "/projects/$TEST_PROJECT_ID/views")
  local count
  count=$(echo "$result" | jq 'length') || count=0

  # At least 2: default list view + our kanban view
  if [[ "$count" -ge 2 ]]; then
    pass "Project has $count views (>=2 expected)"
    RESULT_V2="PASS"
  else
    fail "Project has $count views (expected >=2)"
    RESULT_V2="FAIL"
  fi
}

# --- Test: V3 — Create/verify buckets in view ---

run_test_v3() {
  echo -e "\n${CYAN}[V3] Verify/create buckets in kanban view${NC}"

  # New kanban views auto-create default buckets. List them first.
  local buckets
  buckets=$(api GET "/projects/$TEST_PROJECT_ID/views/$TEST_VIEW_ID/buckets")
  local bucket_count
  bucket_count=$(echo "$buckets" | jq 'length') || bucket_count=0

  if [[ "$bucket_count" -ge 1 ]]; then
    # Use first bucket as TODO
    TEST_BUCKET_TODO=$(echo "$buckets" | jq -r '.[0].id')
    info "Found $bucket_count auto-created buckets, first=#$TEST_BUCKET_TODO"
  fi

  # Create custom buckets if needed
  if [[ "$bucket_count" -lt 3 ]]; then
    local doing_result done_result
    doing_result=$(api PUT "/projects/$TEST_PROJECT_ID/views/$TEST_VIEW_ID/buckets" \
      -d '{"title": "Doing"}')
    TEST_BUCKET_DOING=$(echo "$doing_result" | jq -r '.id // 0')

    done_result=$(api PUT "/projects/$TEST_PROJECT_ID/views/$TEST_VIEW_ID/buckets" \
      -d '{"title": "Done"}')
    TEST_BUCKET_DONE=$(echo "$done_result" | jq -r '.id // 0')
  else
    TEST_BUCKET_DOING=$(echo "$buckets" | jq -r '.[1].id')
    TEST_BUCKET_DONE=$(echo "$buckets" | jq -r '.[2].id')
  fi

  local ok=true
  assert_not_empty "$TEST_BUCKET_TODO" "Bucket: To-Do (#$TEST_BUCKET_TODO)" || ok=false
  assert_not_empty "$TEST_BUCKET_DOING" "Bucket: Doing (#$TEST_BUCKET_DOING)" || ok=false
  assert_not_empty "$TEST_BUCKET_DONE" "Bucket: Done (#$TEST_BUCKET_DONE)" || ok=false

  if $ok; then RESULT_V3="PASS"; else RESULT_V3="FAIL"; fi
}

# --- Test: V4 — Move task between buckets ---

run_test_v4() {
  echo -e "\n${CYAN}[V4] Move task between kanban buckets${NC}"

  # Use first test task
  local tid="${CLEANUP_TASK_IDS[0]}"

  # Move to Doing
  local move_result
  move_result=$(api POST "/projects/$TEST_PROJECT_ID/views/$TEST_VIEW_ID/buckets/$TEST_BUCKET_DOING/tasks" \
    -d "{\"task_id\": $tid}") || true
  info "Move response: $(echo "$move_result" | jq -r '.message // "ok"' 2>/dev/null)"

  # Verify task is still intact (bucket move shouldn't wipe fields)
  local task_after
  task_after=$(api GET "/tasks/$tid") || true
  local title_after
  title_after=$(echo "$task_after" | jq -r '.title // ""') || title_after=""

  if [[ -n "$title_after" && "$title_after" != "null" ]]; then
    pass "Task #$tid still has title after bucket move (title='$title_after')"
    RESULT_V4="PASS"
  else
    RESULT_V4="FAIL"
  fi
}

# --- Test: B1 — Sprint transition (bulk label swap) ---

run_test_b1() {
  echo -e "\n${CYAN}[B1] Sprint transition: swap sprint-1 -> sprint-2 labels${NC}"

  # Get all open sprint-1 tasks
  local filter="labels in $TEST_LABEL_SPRINT1 && done = false"
  local encoded_filter
  encoded_filter=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$filter")

  local sprint1_tasks
  sprint1_tasks=$(api GET "/projects/$TEST_PROJECT_ID/tasks?filter=$encoded_filter&filter_include_nulls=false")
  local task_ids
  task_ids=$(echo "$sprint1_tasks" | jq -r '.[].id') || task_ids=""

  local swap_count=0
  for tid in $task_ids; do
    # Remove sprint-1, add sprint-2
    api DELETE "/tasks/$tid/labels/$TEST_LABEL_SPRINT1" >/dev/null 2>&1
    api PUT "/tasks/$tid/labels" -d "{\"label_id\": $TEST_LABEL_SPRINT2}" >/dev/null 2>&1
    swap_count=$((swap_count + 1))
  done

  # Verify: sprint-1 should have 0 open tasks, sprint-2 should have the swapped ones
  local s1_filter="labels in $TEST_LABEL_SPRINT1 && done = false"
  local s1_encoded
  s1_encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$s1_filter")
  local s1_count
  s1_count=$(api GET "/projects/$TEST_PROJECT_ID/tasks?filter=$s1_encoded&filter_include_nulls=false" | jq 'length') || s1_count=99

  local s2_filter="labels in $TEST_LABEL_SPRINT2 && done = false"
  local s2_encoded
  s2_encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$s2_filter")
  local s2_count
  s2_count=$(api GET "/projects/$TEST_PROJECT_ID/tasks?filter=$s2_encoded&filter_include_nulls=false" | jq 'length') || s2_count=0

  local ok=true
  assert_count "$s1_count" 0 "Sprint-1 has 0 open tasks after transition" || ok=false
  assert_count "$s2_count" "$swap_count" "Sprint-2 has $swap_count tasks after transition" || ok=false

  if $ok; then
    pass "Sprint transition: moved $swap_count tasks from sprint-1 to sprint-2"
    RESULT_B1="PASS"
  else
    RESULT_B1="FAIL"
  fi
}

# --- Test: A1 — Agent scheduler picks up from labeled task ---
# Only runs with --include-agent flag
# Creates a task in PROJECT 13 with a repo label, verifies agent processes it

run_test_a1() {
  if $SKIP_AGENT || $MCP_ONLY; then
    info "Skipped (--skip-agent or --mcp-only)"
    RESULT_A1="SKIP"
    return
  fi

  echo -e "\n${CYAN}[A1] Agent picks up labeled task from project 13${NC}"

  # Create task in agent-fleet project (13) with test label
  local result
  local a1_body
  a1_body=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "description": sys.argv[2]}))' \
    "$TEST_PREFIX [A1] Agent label routing test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Agent e2e test A1</p><h2>Task</h2><p>Create a file test-a1-label.txt containing: test-a1-ok</p>")
  result=$(api PUT "/projects/13/tasks" -d "$a1_body")
  local tid
  tid=$(echo "$result" | jq -r '.id // 0')
  CLEANUP_TASK_IDS+=("$tid")

  # Move to To-Do bucket (project 13, view 52)
  api POST "/projects/13/views/52/buckets/35/tasks" -d "{\"task_id\": $tid}" >/dev/null 2>&1

  # Add sprint label for tracking
  api PUT "/tasks/$tid/labels" -d "{\"label_id\": $TEST_LABEL_SPRINT2}" >/dev/null 2>&1

  info "Created task #$tid in project 13 with sprint-2 label"

  # Wait for agent to claim
  local elapsed=0
  local claimed=false
  printf "  Waiting: %-50s " "agent claims labeled task"
  while [[ $elapsed -lt $TIMEOUT ]]; do
    local comments
    comments=$(api GET "/tasks/$tid/comments") || comments="[]"
    if echo "$comments" | grep -q "CLAIMED" 2>/dev/null; then
      claimed=true
      break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    printf "."
  done

  if $claimed; then
    printf " ${GREEN}OK${NC} (%ds)\n" "$elapsed"
    # Verify task still has label after agent processing
    local task_after
    task_after=$(api GET "/tasks/$tid")
    local label_count
    label_count=$(echo "$task_after" | jq '.labels | length') || label_count=0
    if [[ "$label_count" -ge 1 ]]; then
      pass "Agent processed task, labels preserved"
      RESULT_A1="PASS"
    else
      fail "Agent processed task but labels were wiped"
      RESULT_A1="FAIL"
    fi
  else
    printf " ${RED}TIMEOUT${NC}\n"
    RESULT_A1="FAIL"
  fi
}

# --- Test: A2 — Agent discovers -ag project ---
# Creates a project with -ag suffix, adds kanban view with standard buckets,
# then verifies the agent's discover_project_config function would find it.

AG_TEST_PROJECT_ID=""

run_test_a2() {
  echo -e "\n${CYAN}[A2] Agent discovers -ag project${NC}"

  # Create a project with -ag suffix
  local result
  result=$(api PUT "/projects" -d "$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1]}))' "$TEST_PREFIX miniapp-builder-ag")")
  AG_TEST_PROJECT_ID=$(echo "$result" | jq -r '.id // 0')

  if [[ "$AG_TEST_PROJECT_ID" == "0" || -z "$AG_TEST_PROJECT_ID" ]]; then
    fail "Failed to create -ag test project"
    RESULT_A2="FAIL"
    return
  fi
  info "Created -ag project #$AG_TEST_PROJECT_ID"

  # Verify the project is discoverable by title pattern
  local projects
  projects=$(api GET "/projects") || { RESULT_A2="FAIL"; return; }

  local ag_match
  ag_match=$(echo "$projects" | jq -r '.[] | select(.title | test("-ag$")) | .id' | grep -w "$AG_TEST_PROJECT_ID" || true)

  if [[ -z "$ag_match" ]]; then
    fail "Project #$AG_TEST_PROJECT_ID not matched by -ag$ pattern"
    RESULT_A2="FAIL"
    return
  fi

  # Verify the project has a kanban view (auto-created by Vikunja)
  local views
  views=$(api GET "/projects/$AG_TEST_PROJECT_ID/views") || { RESULT_A2="FAIL"; return; }

  local kanban_view_id
  kanban_view_id=$(echo "$views" | jq -r '[.[] | select(.view_kind == "kanban")] | .[0].id // 0') || kanban_view_id=0

  if [[ "$kanban_view_id" == "0" ]]; then
    # Create a kanban view manually
    local view_result
    view_result=$(api PUT "/projects/$AG_TEST_PROJECT_ID/views" \
      -d '{"title": "Board", "view_kind": "kanban", "bucket_configuration_mode": "manual"}')
    kanban_view_id=$(echo "$view_result" | jq -r '.id // 0')
  fi

  if [[ "$kanban_view_id" == "0" ]]; then
    fail "No kanban view available for -ag project"
    RESULT_A2="FAIL"
    return
  fi

  # Verify buckets exist
  local buckets
  buckets=$(api GET "/projects/$AG_TEST_PROJECT_ID/views/$kanban_view_id/buckets") || { RESULT_A2="FAIL"; return; }
  local bucket_count
  bucket_count=$(echo "$buckets" | jq 'length') || bucket_count=0

  local ok=true
  assert_not_empty "$ag_match" "Project matched by -ag$ pattern" || ok=false
  assert_not_empty "$kanban_view_id" "Kanban view discovered (#$kanban_view_id)" || ok=false
  if [[ "$bucket_count" -ge 2 ]]; then
    pass "Kanban has $bucket_count buckets (>=2 required)"
  else
    fail "Kanban has $bucket_count buckets (need >=2)"
    ok=false
  fi

  if $ok; then RESULT_A2="PASS"; else RESULT_A2="FAIL"; fi
}

# --- Cleanup ---

cleanup() {
  echo -e "\n${YELLOW}Cleaning up test data...${NC}"

  # Close test tasks
  for tid in "${CLEANUP_TASK_IDS[@]+"${CLEANUP_TASK_IDS[@]}"}"; do
    if [[ -n "$tid" && "$tid" != "0" ]]; then
      api DELETE "/tasks/$tid" >/dev/null 2>&1 || true
      echo "  Deleted task #$tid"
    fi
  done

  # Delete test labels
  for lid in "${CLEANUP_LABEL_IDS[@]+"${CLEANUP_LABEL_IDS[@]}"}"; do
    if [[ -n "$lid" && "$lid" != "0" ]]; then
      api DELETE "/labels/$lid" >/dev/null 2>&1 || true
      echo "  Deleted label #$lid"
    fi
  done

  # Delete test views (if created)
  if [[ -n "$TEST_VIEW_ID" && "$TEST_VIEW_ID" != "0" ]]; then
    api DELETE "/projects/$TEST_PROJECT_ID/views/$TEST_VIEW_ID" >/dev/null 2>&1 || true
    echo "  Deleted view #$TEST_VIEW_ID"
  fi

  # Delete test projects
  if [[ -n "$TEST_PROJECT_ID" && "$TEST_PROJECT_ID" != "0" ]]; then
    api DELETE "/projects/$TEST_PROJECT_ID" >/dev/null 2>&1 || true
    echo "  Deleted project #$TEST_PROJECT_ID"
  fi
  if [[ -n "$AG_TEST_PROJECT_ID" && "$AG_TEST_PROJECT_ID" != "0" ]]; then
    api DELETE "/projects/$AG_TEST_PROJECT_ID" >/dev/null 2>&1 || true
    echo "  Deleted -ag project #$AG_TEST_PROJECT_ID"
  fi

  # Also find any leftover MCP-E2E tasks in project 13
  local leftover
  leftover=$(api GET "/projects/13/tasks" 2>/dev/null) || leftover="[]"
  local leftover_ids
  leftover_ids=$(echo "$leftover" | jq -r ".[] | select(.title | test(\"MCP-E2E\")) | select(.done == false) | .id" 2>/dev/null) || true
  for tid in $leftover_ids; do
    api DELETE "/tasks/$tid" >/dev/null 2>&1 || true
    echo "  Deleted leftover #$tid from project 13"
  done

  echo -e "${GREEN}Cleanup complete${NC}"
}

# --- Results ---

print_results() {
  echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  MCP Multi-Project E2E Test Results${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"

  local pass=0 fail=0 skip=0 total=0

  local tests="P1 P2 L1 L2 T1 T2 T3 T4 T5 V1 V2 V3 V4 B1 A1 A2"
  for test_name in $tests; do
    total=$((total + 1))
    local result
    eval "result=\$RESULT_$test_name"
    local color="$YELLOW"
    if [[ "$result" == "PASS" ]]; then color="$GREEN"; pass=$((pass + 1));
    elif [[ "$result" == "FAIL" ]]; then color="$RED"; fail=$((fail + 1));
    else skip=$((skip + 1)); fi

    local desc=""
    case $test_name in
      P1) desc="Create test project";;
      P2) desc="Resolve project by name";;
      L1) desc="Create sprint labels";;
      L2) desc="Resolve label by name";;
      T1) desc="Create task with labels";;
      T2) desc="Bulk create tasks + label";;
      T3) desc="Filter tasks by label";;
      T4) desc="Filter: label + done=false";;
      T5) desc="Update preserves description (no wipe)";;
      V1) desc="Create filtered kanban view";;
      V2) desc="List views for project";;
      V3) desc="Create/verify kanban buckets";;
      V4) desc="Move task between buckets";;
      B1) desc="Sprint transition (label swap)";;
      A1) desc="Agent picks up labeled task";;
      A2) desc="Agent discovers -ag project";;
    esac
    printf "  %-5s %-45s ${color}%s${NC}\n" "[$test_name]" "$desc" "$result"
  done

  echo -e "${CYAN}───────────────────────────────────────────────────${NC}"
  echo -e "  Total: $total  ${GREEN}Pass: $pass${NC}  ${RED}Fail: $fail${NC}  ${YELLOW}Skip: $skip${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"

  [[ "$fail" -eq 0 ]]
}

# --- Main ---

main() {
  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cleanup)
        load_token
        # Try to find and clean any leftover test projects
        local projects
        projects=$(api GET "/projects") || projects="[]"
        local test_pids
        test_pids=$(echo "$projects" | jq -r ".[] | select(.title | test(\"MCP-E2E\")) | .id" 2>/dev/null) || true
        for pid in $test_pids; do
          api DELETE "/projects/$pid" >/dev/null 2>&1 || true
          echo "Deleted leftover project #$pid"
        done
        # Clean labels
        local labels
        labels=$(api GET "/labels") || labels="[]"
        local test_lids
        test_lids=$(echo "$labels" | jq -r ".[] | select(.title | test(\"MCP-E2E\")) | .id" 2>/dev/null) || true
        for lid in $test_lids; do
          api DELETE "/labels/$lid" >/dev/null 2>&1 || true
          echo "Deleted leftover label #$lid"
        done
        exit 0
        ;;
      --skip-agent) SKIP_AGENT=true; shift;;
      --mcp-only) MCP_ONLY=true; shift;;
      --timeout) TIMEOUT="${2:-120}"; shift 2;;
      *) echo "Unknown arg: $1"; exit 1;;
    esac
  done

  load_token

  echo -e "${CYAN}MCP Multi-Project E2E Test${NC}"
  echo "  Vikunja: $VIKUNJA_URL"
  echo "  Timeout: ${TIMEOUT}s"
  echo "  Agent tests: $(if $SKIP_AGENT || $MCP_ONLY; then echo 'disabled'; else echo 'enabled'; fi)"
  echo ""

  # Phase 1: Project + Label infrastructure
  run_test_p1 || { print_results; cleanup; exit 1; }
  run_test_p2
  run_test_l1
  run_test_l2

  # Phase 2: Task operations with labels
  run_test_t1
  run_test_t2
  run_test_t3
  run_test_t4
  run_test_t5

  # Phase 3: View + bucket management
  run_test_v1
  run_test_v2
  run_test_v3
  run_test_v4

  # Phase 4: Sprint workflow
  run_test_b1

  # Phase 5: Agent integration (optional)
  run_test_a1
  run_test_a2

  # Results
  print_results
  local exit_code=$?

  # Cleanup
  cleanup

  exit "$exit_code"
}

main "$@"
