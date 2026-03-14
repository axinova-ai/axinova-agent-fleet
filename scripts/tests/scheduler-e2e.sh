#!/usr/bin/env bash
# ============================================================
# Agent Scheduler E2E Test
# ============================================================
# Creates mock tasks in Vikunja, waits for agents to process them,
# then verifies each scheduling scenario passed.
#
# All tasks are created upfront and polled concurrently for speed.
#
# Usage:
#   ./scripts/tests/scheduler-e2e.sh              # Run all tests
#   ./scripts/tests/scheduler-e2e.sh --cleanup     # Just close leftover test tasks
#   ./scripts/tests/scheduler-e2e.sh --timeout 300  # Custom timeout (default: 240s)
#
# Prerequisites:
#   - Vikunja accessible at localhost:3456 (SSH tunnel)
#   - Agents running on agent01 + agent02
#   - jq, curl installed
# ============================================================
set -euo pipefail

VIKUNJA_URL="http://localhost:3456/api/v1"
VIKUNJA_TOKEN=""
PROJECT_ID=13
VIEW_ID=52
BUCKET_TODO=35
TIMEOUT="${TIMEOUT:-240}"
TEST_PREFIX="[SCHED-TEST]"
POLL_INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Helpers ---

load_token() {
  local env_file=""
  for candidate in "$HOME/.config/axinova/mcp.env" "$HOME/.config/axinova/vikunja.env" "$HOME/.config/axinova/secrets.env"; do
    if [[ -f "$candidate" ]] && grep -q 'APP_VIKUNJA__TOKEN' "$candidate" 2>/dev/null; then
      env_file="$candidate"
      break
    fi
  done
  if [[ -z "$env_file" ]]; then
    echo "ERROR: No env file with APP_VIKUNJA__TOKEN found in ~/.config/axinova/" >&2
    exit 1
  fi
  VIKUNJA_TOKEN=$(grep 'APP_VIKUNJA__TOKEN' "$env_file" | cut -d= -f2)
  if [[ -z "$VIKUNJA_TOKEN" ]]; then
    echo "ERROR: APP_VIKUNJA__TOKEN empty in $env_file" >&2
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
  local json_body
  json_body=$(jq -n --arg t "$title" --arg d "$description" '{title: $t, description: $d}')
  local result
  result=$(vikunja_api PUT "/projects/$PROJECT_ID/tasks" -d "$json_body")
  local task_id
  task_id=$(echo "$result" | jq -r '.id // 0')
  if [[ "$task_id" == "0" || -z "$task_id" ]]; then
    echo "ERROR: Failed to create task: $title" >&2
    return 1
  fi
  vikunja_api POST "/projects/$PROJECT_ID/views/$VIEW_ID/buckets/$BUCKET_TODO/tasks" \
    -d "{\"task_id\": $task_id}" >/dev/null 2>&1 || true
  echo "$task_id"
}

get_task_comments() {
  vikunja_api GET "/tasks/$1/comments" 2>/dev/null
}

has_comment_matching() {
  local task_id="$1" pattern="$2"
  local comments
  comments=$(get_task_comments "$task_id") || return 1
  echo "$comments" | grep -q "$pattern"
}

get_claim_count() {
  local task_id="$1"
  local comments
  comments=$(get_task_comments "$task_id") || echo "[]"
  echo "$comments" | jq '[.[] | select(.comment | test("CLAIMED"))] | length' 2>/dev/null || echo "0"
}

close_task() {
  local task_id="$1"
  local full_task
  full_task=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null) || true
  if [[ -n "$full_task" ]]; then
    local clean
    clean=$(echo "$full_task" | jq '.done = true' 2>/dev/null) || clean='{"done": true}'
    vikunja_api POST "/tasks/$task_id" -d "$clean" >/dev/null 2>&1
  fi
}

mark_done() {
  local task_id="$1"
  local full_task
  full_task=$(vikunja_api GET "/tasks/$task_id" 2>/dev/null) || true
  if [[ -n "$full_task" ]]; then
    local updated
    updated=$(echo "$full_task" | jq '.done = true' 2>/dev/null) || updated='{"done": true}'
    vikunja_api POST "/tasks/$task_id" -d "$updated" >/dev/null 2>&1
  fi
}

# --- Cleanup ---

cleanup_test_tasks() {
  echo -e "\n${YELLOW}Cleaning up test tasks...${NC}"
  for tid in "${ALL_TASK_IDS[@]+"${ALL_TASK_IDS[@]}"}"; do
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

# --- Results ---

declare -a ALL_TASK_IDS=()
RESULT_T1="SKIP" RESULT_T2="SKIP" RESULT_T3="SKIP"
RESULT_T4="SKIP" RESULT_T5="SKIP" RESULT_T6="SKIP"
RESULT_T7="SKIP"

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
    printf "  %-5s %-50s ${color}%s${NC}\n" "[$test_name]" "$desc" "$result"
  done

  echo -e "${CYAN}───────────────────────────────────────────${NC}"
  echo -e "  Total: $total  ${GREEN}Pass: $pass${NC}  ${RED}Fail: $fail${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════${NC}"

  [[ "$fail" -eq 0 ]]
}

# --- Main ---

main() {
  if [[ "${1:-}" == "--cleanup" ]]; then
    load_token
    ALL_TASK_IDS=()
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
  echo "  Timeout: ${TIMEOUT}s"
  echo ""

  # ================================================================
  # Phase 1: Create ALL tasks upfront
  # ================================================================
  echo -e "${CYAN}Creating all test tasks...${NC}"

  # T1: Priority 4 → auto-escalate
  local T1_ID
  T1_ID=$(create_task \
    "$TEST_PREFIX [T1] Priority escalation test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T1</p><h2>Task</h2><p>This task has priority 4 and should auto-escalate.</p>")
  ALL_TASK_IDS+=("$T1_ID")
  vikunja_api POST "/tasks/$T1_ID" -d '{"priority": 4}' >/dev/null 2>&1
  echo "  T1 (priority escalation): #$T1_ID"

  # T2: MODEL: codex → Codex CLI
  local T2_ID
  T2_ID=$(create_task \
    "$TEST_PREFIX [T2] Echo codex route test — axinova-miniapp-builder-go" \
    "<p>MODEL: codex</p><p>$TEST_PREFIX Scheduler test T2</p><h2>Task</h2><p>Create a file <code>test-t2-codex.txt</code> containing: test-t2-ok</p>")
  ALL_TASK_IDS+=("$T2_ID")
  echo "  T2 (codex routing):       #$T2_ID"

  # T3: MODEL: founder → agents skip (negative test)
  local T3_ID
  T3_ID=$(create_task \
    "$TEST_PREFIX [T3] Founder guard test — axinova-miniapp-builder-go" \
    "<p>MODEL: founder</p><p>$TEST_PREFIX Scheduler test T3</p><h2>Task</h2><p>Must NOT be picked up.</p>")
  ALL_TASK_IDS+=("$T3_ID")
  echo "  T3 (founder guard):       #$T3_ID"

  # T4: No MODEL → default Codex CLI
  local T4_ID
  T4_ID=$(create_task \
    "$TEST_PREFIX [T4] Default model test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T4</p><h2>Task</h2><p>Create a file <code>test-t4-default.txt</code> containing: test-t4-ok</p>")
  ALL_TASK_IDS+=("$T4_ID")
  echo "  T4 (default model):       #$T4_ID"

  # T5: Race condition → only 1 agent claims
  local T5_ID
  T5_ID=$(create_task \
    "$TEST_PREFIX [T5] Race condition test — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T5</p><h2>Task</h2><p>Create a file <code>test-t5-race.txt</code> containing: test-t5-ok</p>")
  ALL_TASK_IDS+=("$T5_ID")
  echo "  T5 (race condition):      #$T5_ID"

  # T6: Complexity → auto-escalate
  local T6_ID
  T6_ID=$(create_task \
    "$TEST_PREFIX [T6] Full multi-step wizard with admin panel migration refactor redesign onboarding — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX Scheduler test T6</p><h2>Task</h2><p>Multi-step wizard with onboarding migration and admin panel redesign. Refactor the entire flow.</p>")
  ALL_TASK_IDS+=("$T6_ID")
  echo "  T6 (complexity):          #$T6_ID"

  # T7: Blocked dependency (2 tasks + relation)
  local T7_BLOCKER_ID T7_BLOCKED_ID
  T7_BLOCKER_ID=$(create_task \
    "$TEST_PREFIX [T7-blocker] Dependency blocker — axinova-miniapp-builder-go" \
    "<p>MODEL: founder</p><p>$TEST_PREFIX T7 blocker task.</p>")
  ALL_TASK_IDS+=("$T7_BLOCKER_ID")

  T7_BLOCKED_ID=$(create_task \
    "$TEST_PREFIX [T7-blocked] Depends on blocker — axinova-miniapp-builder-go" \
    "<p>$TEST_PREFIX T7 blocked task.</p><h2>Task</h2><p>Create a file <code>test-t7.txt</code> containing: test-t7-ok</p>")
  ALL_TASK_IDS+=("$T7_BLOCKED_ID")

  vikunja_api PUT "/tasks/$T7_BLOCKED_ID/relations" \
    -d "{\"other_task_id\": $T7_BLOCKER_ID, \"relation_kind\": \"blocked\"}" >/dev/null 2>&1
  echo "  T7 (blocked dep):         #$T7_BLOCKED_ID blocked by #$T7_BLOCKER_ID"

  local start_time
  start_time=$(date +%s)
  echo ""

  # ================================================================
  # Phase 2: Poll all positive tests concurrently
  # ================================================================
  # Track which tests are still pending
  local t1_done=false t2_done=false t4_done=false t5_done=false t6_done=false
  local t7_phase1_done=false t7_unblocked=false t7_done=false
  local t3_done=false
  local elapsed=0

  # Minimum wait before checking negative tests (T3, T7-phase1)
  # Need at least 2 full poll cycles (~240s + jitter) for T3 to be sure
  # T7-phase1 needs fewer cycles since agents are already polling
  local T3_MIN_WAIT="$TIMEOUT"
  local T7_PHASE1_MIN_WAIT=$(( TIMEOUT / 2 ))

  echo -e "${CYAN}Polling all tests concurrently...${NC}"

  while [[ $elapsed -lt $((TIMEOUT * 2)) ]]; do
    local all_resolved=true

    # --- T1: Priority escalation ---
    if [[ "$t1_done" == "false" ]]; then
      if has_comment_matching "$T1_ID" "NEEDS FOUNDER"; then
        printf "  ${GREEN}✓${NC} T1 priority escalation     (%ds)\n" "$elapsed"
        RESULT_T1="PASS"
        t1_done=true
      else
        all_resolved=false
      fi
    fi

    # --- T2: Codex routing ---
    if [[ "$t2_done" == "false" ]]; then
      if has_comment_matching "$T2_ID" "codex-exec"; then
        printf "  ${GREEN}✓${NC} T2 codex routing            (%ds)\n" "$elapsed"
        RESULT_T2="PASS"
        t2_done=true
      else
        all_resolved=false
      fi
    fi

    # --- T4: Default model ---
    if [[ "$t4_done" == "false" ]]; then
      if has_comment_matching "$T4_ID" "codex-exec"; then
        printf "  ${GREEN}✓${NC} T4 default model            (%ds)\n" "$elapsed"
        RESULT_T4="PASS"
        t4_done=true
      else
        all_resolved=false
      fi
    fi

    # --- T5: Race condition ---
    if [[ "$t5_done" == "false" ]]; then
      if has_comment_matching "$T5_ID" "CLAIMED"; then
        local claim_count
        claim_count=$(get_claim_count "$T5_ID")
        if [[ "$claim_count" -eq 1 ]]; then
          printf "  ${GREEN}✓${NC} T5 race (1 claim)           (%ds)\n" "$elapsed"
          RESULT_T5="PASS"
        else
          printf "  ${RED}✗${NC} T5 race (%s claims!)        (%ds)\n" "$claim_count" "$elapsed"
          RESULT_T5="FAIL"
        fi
        t5_done=true
      else
        all_resolved=false
      fi
    fi

    # --- T6: Complexity escalation ---
    if [[ "$t6_done" == "false" ]]; then
      if has_comment_matching "$T6_ID" "NEEDS FOUNDER"; then
        printf "  ${GREEN}✓${NC} T6 complexity escalation    (%ds)\n" "$elapsed"
        RESULT_T6="PASS"
        t6_done=true
      else
        all_resolved=false
      fi
    fi

    # --- T7 Phase 1: Verify blocked task NOT claimed ---
    if [[ "$t7_phase1_done" == "false" && "$elapsed" -ge "$T7_PHASE1_MIN_WAIT" ]]; then
      local blocked_claims
      blocked_claims=$(get_claim_count "$T7_BLOCKED_ID")
      if [[ "$blocked_claims" == "0" ]]; then
        printf "  ${GREEN}✓${NC} T7 phase1 (not claimed)     (%ds)\n" "$elapsed"
        t7_phase1_done=true
      else
        printf "  ${RED}✗${NC} T7 phase1 FAIL — blocked task claimed before blocker done!\n"
        RESULT_T7="FAIL"
        t7_phase1_done=true
        t7_done=true
      fi
    fi

    # --- T7: Unblock after phase 1 passes ---
    if [[ "$t7_phase1_done" == "true" && "$t7_unblocked" == "false" && "$RESULT_T7" != "FAIL" ]]; then
      echo "  T7 unblocking: marking blocker #$T7_BLOCKER_ID as done..."
      mark_done "$T7_BLOCKER_ID"
      t7_unblocked=true
    fi

    # --- T7 Phase 2: Verify blocked task gets picked up ---
    if [[ "$t7_unblocked" == "true" && "$t7_done" == "false" ]]; then
      if has_comment_matching "$T7_BLOCKED_ID" "CLAIMED"; then
        printf "  ${GREEN}✓${NC} T7 phase2 (picked up)       (%ds)\n" "$elapsed"
        RESULT_T7="PASS"
        t7_done=true
      else
        all_resolved=false
      fi
    elif [[ "$t7_done" == "false" ]]; then
      all_resolved=false
    fi

    # --- T3: Negative test — check after minimum wait ---
    if [[ "$t3_done" == "false" && "$elapsed" -ge "$T3_MIN_WAIT" ]]; then
      local t3_claims
      t3_claims=$(get_claim_count "$T3_ID")
      local t3_pct
      t3_pct=$(vikunja_api GET "/tasks/$T3_ID" 2>/dev/null | jq -r '.percent_done // 0') || t3_pct="0"
      if [[ "$t3_claims" == "0" && "$t3_pct" == "0" ]]; then
        printf "  ${GREEN}✓${NC} T3 founder guard (skipped)  (%ds)\n" "$elapsed"
        RESULT_T3="PASS"
      else
        printf "  ${RED}✗${NC} T3 founder guard FAIL — task was claimed! (claims=%s, pct=%s)\n" "$t3_claims" "$t3_pct"
        RESULT_T3="FAIL"
      fi
      t3_done=true
    elif [[ "$t3_done" == "false" ]]; then
      all_resolved=false
    fi

    # All tests resolved?
    if [[ "$all_resolved" == "true" ]]; then
      break
    fi

    sleep "$POLL_INTERVAL"
    elapsed=$(( $(date +%s) - start_time ))
  done

  # Mark any remaining tests as FAIL (timed out)
  if [[ "$t1_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T1 priority escalation     TIMEOUT\n"
    RESULT_T1="FAIL"
  fi
  if [[ "$t2_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T2 codex routing            TIMEOUT\n"
    RESULT_T2="FAIL"
  fi
  if [[ "$t3_done" == "false" ]]; then
    # T3 never got checked — treat as pass (agents didn't claim it)
    local t3_claims
    t3_claims=$(get_claim_count "$T3_ID")
    if [[ "$t3_claims" == "0" ]]; then
      printf "  ${GREEN}✓${NC} T3 founder guard (skipped)  (%ds)\n" "$elapsed"
      RESULT_T3="PASS"
    else
      printf "  ${RED}✗${NC} T3 founder guard FAIL\n"
      RESULT_T3="FAIL"
    fi
  fi
  if [[ "$t4_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T4 default model            TIMEOUT\n"
    RESULT_T4="FAIL"
  fi
  if [[ "$t5_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T5 race condition           TIMEOUT\n"
    RESULT_T5="FAIL"
  fi
  if [[ "$t6_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T6 complexity escalation    TIMEOUT\n"
    RESULT_T6="FAIL"
  fi
  if [[ "$t7_done" == "false" ]]; then
    printf "  ${RED}✗${NC} T7 blocked dependency       TIMEOUT\n"
    RESULT_T7="FAIL"
  fi

  local total_elapsed=$(( $(date +%s) - start_time ))
  echo ""
  echo -e "  Total test time: ${total_elapsed}s"

  print_results
  local exit_code=$?

  cleanup_test_tasks

  exit "$exit_code"
}

main "$@"
