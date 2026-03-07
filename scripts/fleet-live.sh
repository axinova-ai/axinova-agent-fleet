#!/usr/bin/env bash
# Live fleet status — shows builder activity and task queue at a glance
# Usage: ./scripts/fleet-live.sh              (one-shot)
#        watch -n10 ./scripts/fleet-live.sh   (auto-refresh every 10s)
#        ssh agent01-vpn './workspace/axinova-agent-fleet/scripts/fleet-live.sh'  (run on M4)

set -uo pipefail

# Vikunja config
source ~/.config/axinova/vikunja.env 2>/dev/null || true
VIKUNJA_URL="${VIKUNJA_URL:-http://localhost:3456}"
TOKEN="${APP_VIKUNJA__TOKEN:-}"

# Colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[0;90m'
NC='\033[0m'

printf "${BOLD}Axinova Fleet Live — %s${NC}\n" "$(date '+%H:%M:%S')"
echo "──────────────────────────────────────────────────────"

# --- Task Queue ---
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: No Vikunja token. Set APP_VIKUNJA__TOKEN."
  exit 1
fi

tasks=$(curl -sf "${VIKUNJA_URL}/api/v1/projects/13/tasks?per_page=50" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if [[ -z "$tasks" ]]; then
  echo "ERROR: Cannot reach Vikunja at $VIKUNJA_URL"
  exit 1
fi

echo "$tasks" | python3 -c "
import sys, json

tasks = json.load(sys.stdin)
open_tasks = [t for t in tasks if not t.get('done')]
unclaimed = [t for t in open_tasks if t.get('percent_done', 0) == 0]
doing = [t for t in open_tasks if 0 < t.get('percent_done', 0) < 0.8]
review = [t for t in open_tasks if 0.8 <= t.get('percent_done', 0) < 1]

def labels_str(t):
    return ', '.join(l['title'] for l in (t.get('labels') or [])) or '-'

def short_title(t, max_len=55):
    title = t['title']
    return title[:max_len] + '...' if len(title) > max_len else title

# Queue
print(f'\033[1mQueue:\033[0m {len(unclaimed)} waiting | {len(doing)} doing | {len(review)} review')
print()

if doing:
    print('\033[0;33m  DOING:\033[0m')
    for t in doing:
        print(f'    #{t[\"index\"]:>3}  [{labels_str(t):<12}]  {short_title(t)}')

if unclaimed:
    print('\033[0;36m  QUEUE:\033[0m')
    for t in unclaimed[:8]:
        print(f'    #{t[\"index\"]:>3}  [{labels_str(t):<12}]  {short_title(t)}')
    if len(unclaimed) > 8:
        print(f'    ... +{len(unclaimed)-8} more')

if review:
    print('\033[0;32m  REVIEW:\033[0m')
    for t in review:
        print(f'    #{t[\"index\"]:>3}  [{labels_str(t):<12}]  {short_title(t)}')

if not open_tasks:
    print('  \033[0;90m(no open tasks)\033[0m')
" 2>/dev/null

echo ""
echo "──────────────────────────────────────────────────────"

# --- Builder Activity (from logs) ---
printf "${BOLD}Builders:${NC}\n"
LOG_DIR="$HOME/logs"

for i in $(seq 1 16); do
  log_file="$LOG_DIR/agent-builder-${i}.log"
  [[ ! -f "$log_file" ]] && continue

  last_line=$(tail -1 "$log_file" 2>/dev/null)
  timestamp=$(echo "$last_line" | grep -oE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?\]' | head -1 | tr -d '[]')

  # Check last few lines for better state detection
  last_lines=$(tail -5 "$log_file" 2>/dev/null)
  last_task=$(echo "$last_lines" | grep -oE 'task #[0-9]+|Task #[0-9]+' | tail -1 | grep -oE '#[0-9]+')

  if echo "$last_lines" | grep -q "Executing task\|STARTED\|Codex\|Kimi\|codex exec\|Attempting\|Selected model\|wiki task"; then
    printf "  ${YELLOW}builder-%-2d${NC}  working  %-5s  %s\n" "$i" "${last_task:-}" "${timestamp:-}"
  elif echo "$last_lines" | grep -q "sleeping\|No tasks found"; then
    printf "  ${DIM}builder-%-2d  idle           %s${NC}\n" "$i" "${timestamp:-}"
  elif echo "$last_lines" | grep -q "Claiming\|Found task"; then
    printf "  ${CYAN}builder-%-2d${NC}  claiming %-5s  %s\n" "$i" "${last_task:-}" "${timestamp:-}"
  elif echo "$last_lines" | grep -q "COMPLETED\|IN REVIEW\|PR:"; then
    printf "  ${GREEN}builder-%-2d${NC}  done     %-5s  %s\n" "$i" "${last_task:-}" "${timestamp:-}"
  elif echo "$last_lines" | grep -q "BLOCKED\|ERROR\|ESCALAT\|skipped"; then
    printf "  ${RED}builder-%-2d  blocked  %-5s  %s${NC}\n" "$i" "${last_task:-}" "${timestamp:-}"
  elif echo "$last_lines" | grep -q "Polling\|Starting agent"; then
    printf "  ${DIM}builder-%-2d  polling        %s${NC}\n" "$i" "${timestamp:-}"
  else
    printf "  ${DIM}builder-%-2d  idle           %s${NC}\n" "$i" "${timestamp:-}"
  fi
done

# --- LLM Availability ---
echo "──────────────────────────────────────────────────────"
printf "${BOLD}LLMs:${NC}\n"

# Check from latest builder startup log
latest_log=$(ls -t "$LOG_DIR"/agent-builder-*.log 2>/dev/null | head -1)
if [[ -n "$latest_log" ]]; then
  models_line=$(grep "Models available" "$latest_log" 2>/dev/null | tail -1)
  if [[ -n "$models_line" ]]; then
    codex_ok=$(echo "$models_line" | grep -o 'codex=yes' || true)
    kimi_ok=$(echo "$models_line" | grep -o 'kimi=yes' || true)
    ollama_ok=$(echo "$models_line" | grep -o 'ollama=yes' || true)

    [[ -n "$codex_ok" ]] && printf "  ${GREEN}codex-cli   ✓ primary${NC}\n" || printf "  ${RED}codex-cli   ✗ unavailable${NC}\n"
    [[ -n "$kimi_ok" ]] && printf "  ${GREEN}kimi-k2.5   ✓ fallback${NC}\n" || printf "  ${RED}kimi-k2.5   ✗ unavailable${NC}\n"
    [[ -n "$ollama_ok" ]] && printf "  ${GREEN}ollama      ✓ local${NC}\n" || printf "  ${RED}ollama      ✗ unavailable${NC}\n"
  else
    printf "  ${DIM}(no model info in logs)${NC}\n"
  fi

  # Check if any recent tasks used fallback
  recent_fallback=$(grep -l "FALLBACK" "$LOG_DIR"/agent-builder-*.log 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$recent_fallback" -gt 0 ]]; then
    printf "  ${YELLOW}⚠ $recent_fallback builder(s) hit fallback recently${NC}\n"
  fi
else
  printf "  ${DIM}(no builder logs found)${NC}\n"
fi

echo ""
printf "${DIM}Run: watch -n10 %s${NC}\n" "$0"
