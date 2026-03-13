#!/usr/bin/env bash
# ============================================================
# Agent Scheduler E2E Test
# ============================================================
# Creates mock tasks in Vikunja, waits for agents to process them,
# then verifies each scheduling scenario passed.
#
# Usage:
#   ./scripts/test-scheduler-e2e.sh              # Run all tests
#   ./scripts/test-scheduler-e2e.sh --cleanup     # Just close leftover test tasks
#   ./scripts/test-scheduler-e2e.sh --timeout 300  # Custom timeout (default: 240s)
#
# Prerequisites:
#   - Vikunja accessible at localhost:3456 (SSH tunnel)
#   - Agents running on agent01 + agent02
#   - jq, curl, python3 installed
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VIKUNJA_URL="http://localhost:3456/api/v1"
VIKUNJA_TOKEN=""
PROJECT_ID=13
VIEW_ID=52
BUCKET_TODO=35
BUCKET_DOING=36
BUCKET_DONE=37
BUCKET_NEEDS_FOUNDER=38
BUCKET_IN_REVIEW=39
TIMEOUT="${TIMEOUT:-240}"
TEST_PREFIX="[SCHED-TEST]"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

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

vikunja_api() {
  local method="$1" path="$2"
  shift 2
  curl -s -X "$method" "${VIKUNJA_URL}${path}" \
    -H "Authorization: Bearer $VIKUNJA_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

create_task() {
  local title="$1" description="$2"
  local result
  local json_body
  json_body=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "description": sys.argv[2]}))' "$title" "$description")
  result=$(vikunja_api PUT "/projects/$PROJECT_ID/tasks" -d "$json_body")
  local task_id
  task_id=$(echo "$result" | jq -r '.id // 0')
  if [[ "$task_id" == "0" || -z "$task_id" ]]; then
    echo "ERROR: Failed to create task: $title" >&2
    return 1
  fi
  # Move to To-Do bucket
  vikunja_api POST "/projects/$PROJECT_ID/views/$VIEW_ID/buckets/$BUCKET_TODO/tasks" \
    -d "{\"task_id\": $task_id}" >/dev/null 2>&1 || true
  echo "$task_id"
}

get_task() {
  local task_id="$1"
  vikunja_api GET "/tasks/$task_id" 2>/dev/null
}

get_task_comments() {
  local task_id="$1"
  vikunja_api GET "/tasks/$task_id/comments" 2>/dev/null
}

close_task() {
  local task_id="$1"
  # GET full task first to avoid wiping fields
  local full_task
  full_task=$(get_task "$task_id") || true
  if [[ -n "$full_task" ]]; then
    local clean
    clean=$(echo "$full_task" | python3 -c "
import json, sys
raw = sys.stdin.read()
clean = ''.join(c if c in '\n\t' or ord(c) >= 32 else '' for c in raw)
task = json.loads(clean)
task['done'] = True
print(json.dumps(task))
" 2>/dev/null) || clean='{"done": true}'
    vikunja_api POST "/tasks/$task_id" -d "$clean" >/dev/null 2>&1
  fi
}

wait_for_condition() {
  local description="$1"
  local check_fn="$2"
  local max_wait="$3"
  local elapsed=0
  local interval=10

  printf "  Waiting: %-50s " "$description"
  while [[ $elapsed -lt $max_wait ]]; do
    if $check_fn 2>/dev/null; then
      printf "${GREEN}OK${NC} (%ds)\n" "$elapsed"
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    printf "."
  done
  printf "${RED}TIMEOUT${NC} (%ds)\n" "$max_wait"
  return 1
}

# --- Test Definitions ---

declare -a TEST_IDS=()
# Results stored as simple vars (macOS bash 3 lacks associative arrays)
RESULT_T1="SKIP" RESULT_T2="SKIP" RESULT_T3="SKIP"
RESULT_T4="SKIP" RESULT_T5="SKIP" RESULT_T6="SKIP"
RESULT_T7="SKIP"

run_test_t1_priority_escalation() {
  echo -e "\n${CYAN}[T1] Priority 4 — auto-escalate to Needs Founder${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T1] Priority escalation test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T1</p><h2>Task</h2><p>This task has priority 4 and should auto-escalate.</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"
  # Set priority to 4 (hard — founder-only)
  vikunja_api POST "/tasks/$tid" -d '{"priority": 4}' >/dev/null 2>&1

  check_t1() {
    local comments
    comments=$(get_task_comments "$tid") || return 1
    echo "$comments" | grep -q "NEEDS FOUNDER"
  }

  if wait_for_condition "auto-escalated via priority" check_t1 "$TIMEOUT"; then
    RESULT_T1="PASS"
  else
    RESULT_T1="FAIL"
  fi
}

run_test_t2_codex_route() {
  echo -e "\n${CYAN}[T2] MODEL: codex — Codex CLI routing${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T2] Echo codex route test — axinova-miniapp-builder-go" \
    "<p>MODEL: codex</p><p>$TEST_PREFIX Scheduler test T2</p><h2>Task</h2><p>Create a file <code>test-t2-codex.txt</code> in the repo root containing: test-t2-codex-ok</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"

  check_t2() {
    local comments
    comments=$(get_task_comments "$tid") || return 1
    echo "$comments" | grep -q "codex-exec"
  }

  if wait_for_condition "agent uses Codex CLI" check_t2 "$TIMEOUT"; then
    RESULT_T2="PASS"
  else
    RESULT_T2="FAIL"
  fi
}

run_test_t3_founder_guard() {
  echo -e "\n${CYAN}[T3] MODEL: founder — agents must skip${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T3] Founder guard test — axinova-miniapp-builder-go" \
    "<p>MODEL: founder</p><p>$TEST_PREFIX Scheduler test T3</p><h2>Task</h2><p>This task must NOT be picked up by any agent.</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"

  # Wait enough poll cycles for agents to see it, then verify NO claims
  echo "  Waiting ${TIMEOUT}s for agents to poll..."
  sleep "$TIMEOUT"

  local task_json
  task_json=$(get_task "$tid") || true
  local pct
  pct=$(echo "$task_json" | jq -r '.percent_done // 0') || pct="0"
  local comments
  comments=$(get_task_comments "$tid") || comments="[]"
  local claim_count
  claim_count=$(echo "$comments" | jq '[.[] | select(.comment | test("CLAIMED"))] | length' 2>/dev/null) || claim_count=0

  if [[ "$pct" == "0" && "$claim_count" == "0" ]]; then
    printf "  Result: ${GREEN}PASS${NC} — no agent claimed it (pct=%s, claims=%s)\n" "$pct" "$claim_count"
    RESULT_T3="PASS"
  else
    printf "  Result: ${RED}FAIL${NC} — task was claimed! (pct=%s, claims=%s)\n" "$pct" "$claim_count"
    RESULT_T3="FAIL"
  fi
}

run_test_t4_default_model() {
  echo -e "\n${CYAN}[T4] No MODEL override — default to Codex CLI${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T4] Default model test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T4</p><h2>Task</h2><p>Create a file <code>test-t4-default.txt</code> in the repo root containing: test-t4-default-ok</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"

  check_t4() {
    local comments
    comments=$(get_task_comments "$tid") || return 1
    # Should use codex-exec as default (Kimi fallback removed)
    echo "$comments" | grep -q "codex-exec"
  }

  if wait_for_condition "agent picks up with Codex CLI" check_t4 "$TIMEOUT"; then
    RESULT_T4="PASS"
  else
    RESULT_T4="FAIL"
  fi
}

run_test_t5_race() {
  echo -e "\n${CYAN}[T5] Race condition — only 1 agent claims${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T5] Race condition test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T5</p><h2>Task</h2><p>Create a file <code>test-t5-race.txt</code> in the repo root containing: test-t5-race-ok</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"

  check_t5() {
    local comments
    comments=$(get_task_comments "$tid") || return 1
    echo "$comments" | grep -q "CLAIMED"
  }

  if wait_for_condition "at least 1 agent claims" check_t5 "$TIMEOUT"; then
    # Now verify only 1 agent claimed
    local comments claim_count
    comments=$(get_task_comments "$tid") || comments="[]"
    claim_count=$(echo "$comments" | jq '[.[] | select(.comment | test("CLAIMED"))] | length' 2>/dev/null) || claim_count=0
    if [[ "$claim_count" -eq 1 ]]; then
      printf "  Result: ${GREEN}PASS${NC} — exactly 1 claim\n"
      RESULT_T5="PASS"
    else
      printf "  Result: ${RED}FAIL${NC} — %s claims (expected 1)\n" "$claim_count"
      RESULT_T5="FAIL"
    fi
  else
    RESULT_T5="FAIL"
  fi
}

run_test_t6_complexity() {
  echo -e "\n${CYAN}[T6] Complexity auto-escalation${NC}"
  local tid
  tid=$(create_task \
    "$TEST_PREFIX [T6] Full multi-step wizard with admin panel migration refactor redesign onboarding — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T6</p><h2>Task</h2><p>Multi-step wizard with onboarding migration and admin panel redesign across multiple components and files. Refactor the entire flow.</p>")
  TEST_IDS+=("$tid")
  echo "  Created task #$tid"

  check_t6() {
    local comments
    comments=$(get_task_comments "$tid") || return 1
    echo "$comments" | grep -q "NEEDS FOUNDER"
  }

  if wait_for_condition "auto-escalated to Needs Founder" check_t6 "$TIMEOUT"; then
    RESULT_T6="PASS"
  else
    RESULT_T6="FAIL"
  fi
}

run_test_t7_blocked_dependency() {
  echo -e "\n${CYAN}[T7] Blocked dependency — agents skip tasks with unmet blockers${NC}"

  # Create the blocker task first (will NOT be in To-Do, so agents won't execute it)
  local blocker_tid
  blocker_tid=$(create_task \
    "$TEST_PREFIX [T7-blocker] Dependency blocker — axinova-miniapp-builder-go" \
    "<p>MODEL: founder</p><p>$TEST_PREFIX Scheduler test T7 blocker task. Must be completed before the blocked task can be picked up.</p>")
  TEST_IDS+=("$blocker_tid")
  echo "  Created blocker task #$blocker_tid"

  # Create the blocked task (depends on blocker)
  local blocked_tid
  blocked_tid=$(create_task \
    "$TEST_PREFIX [T7-blocked] Depends on blocker — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T7 blocked task. Should NOT be picked up until blocker is done.</p><h2>Task</h2><p>Create a file <code>test-t7-blocked.txt</code> in the repo root containing: test-t7-blocked-ok</p>")
  TEST_IDS+=("$blocked_tid")
  echo "  Created blocked task #$blocked_tid"

  # Create the dependency relation: blocked_tid is blocked by blocker_tid
  vikunja_api PUT "/tasks/$blocked_tid/relations" \
    -d "{\"other_task_id\": $blocker_tid, \"relation_kind\": \"blocked\"}" >/dev/null 2>&1
  echo "  Created relation: #$blocked_tid blocked by #$blocker_tid"

  # Phase 1: Wait and verify the blocked task is NOT claimed (blocker incomplete)
  local phase1_wait=$((TIMEOUT / 2))
  echo "  Phase 1: Waiting ${phase1_wait}s — blocked task should NOT be claimed..."
  sleep "$phase1_wait"

  local task_json
  task_json=$(get_task "$blocked_tid") || true
  local pct
  pct=$(echo "$task_json" | jq -r '.percent_done // 0') || pct="0"
  local comments
  comments=$(get_task_comments "$blocked_tid") || comments="[]"
  local claim_count
  claim_count=$(echo "$comments" | jq '[.[] | select(.comment | test("CLAIMED"))] | length' 2>/dev/null) || claim_count=0

  if [[ "$pct" != "0" || "$claim_count" != "0" ]]; then
    printf "  Phase 1: ${RED}FAIL${NC} — blocked task was claimed before blocker done! (pct=%s, claims=%s)\n" "$pct" "$claim_count"
    RESULT_T7="FAIL"
    return
  fi
  printf "  Phase 1: ${GREEN}OK${NC} — blocked task not claimed (as expected)\n"

  # Phase 2: Mark blocker as done, then verify blocked task gets picked up
  echo "  Phase 2: Marking blocker #$blocker_tid as done..."
  local blocker_full
  blocker_full=$(get_task "$blocker_tid") || true
  if [[ -n "$blocker_full" ]]; then
    local updated
    updated=$(echo "$blocker_full" | python3 -c "
import json, sys
raw = sys.stdin.read()
clean = ''.join(c if c in '\n\t' or ord(c) >= 32 else '' for c in raw)
task = json.loads(clean)
task['done'] = True
print(json.dumps(task))
" 2>/dev/null) || updated='{"done": true}'
    vikunja_api POST "/tasks/$blocker_tid" -d "$updated" >/dev/null 2>&1
  fi

  check_t7_claimed() {
    local comments
    comments=$(get_task_comments "$blocked_tid") || return 1
    echo "$comments" | grep -q "CLAIMED"
  }

  if wait_for_condition "blocked task picked up after blocker done" check_t7_claimed "$TIMEOUT"; then
    RESULT_T7="PASS"
  else
    # Blocked task not picked up even after blocker done — might be timeout
    printf "  Phase 2: ${RED}FAIL${NC} — blocked task not picked up after blocker resolved\n"
    RESULT_T7="FAIL"
  fi
}

# --- Cleanup ---

cleanup_test_tasks() {
  echo -e "\n${YELLOW}Cleaning up test tasks...${NC}"
  # Close tasks created by this run
  for tid in "${TEST_IDS[@]+"${TEST_IDS[@]}"}"; do
    close_task "$tid"
    echo "  Closed #$tid"
  done
  # Also find any leftover SCHED-TEST tasks
  local all_tasks
  all_tasks=$(vikunja_api GET "/projects/$PROJECT_ID/tasks" 2>/dev/null) || true
  if [[ -n "$all_tasks" ]]; then
    local leftover_ids
    leftover_ids=$(echo "$all_tasks" | jq -r '.[] | select(.title | test("SCHED-TEST")) | select(.done == false) | .id' 2>/dev/null) || true
    for tid in $leftover_ids; do
      close_task "$tid"
      echo "  Closed leftover #$tid"
    done
  fi
}

# --- Main ---

print_results() {
  echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
  echo -e "${CYAN}  Agent Scheduler E2E Test Results${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════${NC}"

  local pass=0 fail=0 total=7

  for test_name in T1 T2 T3 T4 T5 T6 T7; do
    local result
    eval "result=\$RESULT_$test_name"
    local color="$YELLOW"
    if [[ "$result" == "PASS" ]]; then color="$GREEN"; pass=$((pass + 1));
    elif [[ "$result" == "FAIL" ]]; then color="$RED"; fail=$((fail + 1)); fi
    local desc=""
    case $test_name in
      T1) desc="Priority 4 -> auto-escalate to Needs Founder";;
      T2) desc="MODEL: codex -> Codex CLI routing";;
      T3) desc="MODEL: founder -> agents skip";;
      T4) desc="No MODEL -> default Codex CLI";;
      T5) desc="Race -> only 1 agent claims";;
      T6) desc="Complexity -> auto-escalation";;
      T7) desc="Blocked dependency -> agents skip until resolved";;
    esac
    printf "  %-5s %-45s ${color}%s${NC}\n" "[$test_name]" "$desc" "$result"
  done

  echo -e "${CYAN}───────────────────────────────────────────${NC}"
  echo -e "  Total: $total  ${GREEN}Pass: $pass${NC}  ${RED}Fail: $fail${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════${NC}"

  [[ "$fail" -eq 0 ]]
}

main() {
  # Parse args
  if [[ "${1:-}" == "--cleanup" ]]; then
    load_token
    TEST_IDS=()
    cleanup_test_tasks
    exit 0
  fi
  if [[ "${1:-}" == "--timeout" ]]; then
    TIMEOUT="${2:-240}"
    shift 2
  fi

  load_token

  echo -e "${CYAN}Agent Scheduler E2E Test${NC}"
  echo "  Vikunja: $VIKUNJA_URL (project $PROJECT_ID)"
  echo "  Timeout per test: ${TIMEOUT}s"
  echo "  Test prefix: $TEST_PREFIX"
  echo ""

  # Run T3 (founder guard) and T6 (complexity) first since they're fast
  # Then run T1, T2, T4, T5 which need LLM execution
  # T3 is special — we need to wait and verify NOTHING happens

  # Fast tests: T5 (race), T6 (complexity), T1 (kimi), T2 (codex), T4 (default)
  # These run in sequence but verify in parallel via polling
  run_test_t6_complexity
  run_test_t5_race
  run_test_t1_priority_escalation
  run_test_t2_codex_route
  run_test_t4_default_model

  # T7 dependency test (has its own internal phases — blocked then unblocked)
  run_test_t7_blocked_dependency

  # T3 runs last because it's a negative test (wait for nothing to happen)
  run_test_t3_founder_guard

  # Results
  print_results
  local exit_code=$?

  # Cleanup
  cleanup_test_tasks

  exit "$exit_code"
}

main "$@"
