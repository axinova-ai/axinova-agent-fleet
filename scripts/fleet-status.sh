#!/usr/bin/env bash
set -uo pipefail

# Axinova Agent Fleet Status Dashboard
# Usage: ./scripts/fleet-status.sh

M4_HOST="agent01@192.168.3.6"
M2_HOST="focusagent02@192.168.3.5"
VIKUNJA_TOKEN="tk_c92243afb12553b93ee222f1f6c242fb0b746800"

echo "==========================================="
echo "  Axinova Agent Fleet Status"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "==========================================="

# --- Vikunja Tasks ---
echo ""
echo "[Vikunja Tasks — Agent Fleet]"
VIKUNJA_URL=""
if curl -sf "http://localhost:3456/api/v1/info" >/dev/null 2>&1; then
  VIKUNJA_URL="http://localhost:3456"
elif curl -sf --max-time 3 "https://vikunja.axinova-internal.xyz/api/v1/info" >/dev/null 2>&1; then
  VIKUNJA_URL="https://vikunja.axinova-internal.xyz"
fi

if [[ -n "$VIKUNJA_URL" ]]; then
  echo "  OK  Vikunja API reachable"
  tasks=$(curl -sf -H "Authorization: Bearer $VIKUNJA_TOKEN" \
    "${VIKUNJA_URL}/api/v1/projects/13/tasks?filter=done=false" 2>/dev/null)
  if [[ -n "$tasks" ]]; then
    echo "$tasks" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
print(f'  Open tasks: {len(tasks)}')
for t in tasks[:10]:
    labels = ', '.join(l['title'] for l in (t.get('labels') or []))
    pct = t.get('percent_done', 0)
    if pct > 0 and pct < 1:
        status = 'IN PROGRESS'
    elif pct >= 1:
        status = 'DONE'
    else:
        status = 'OPEN'
    print(f'    #{t[\"id\"]:>4}  [{status:<11}]  {t[\"title\"]:<50}  ({labels})')
" 2>/dev/null
  else
    echo "  No open tasks"
  fi

  # --- Agent Ledger (latest comments on in-progress tasks) ---
  echo ""
  echo "[Agent Ledger — Recent Activity]"
  if [[ -n "$tasks" ]]; then
    echo "$tasks" | python3 -c "
import sys, json, urllib.request
tasks = json.load(sys.stdin)
in_progress = [t for t in tasks if 0 < t.get('percent_done', 0) < 1]
if not in_progress:
    print('  No in-progress tasks')
    sys.exit(0)
for t in in_progress[:5]:
    tid = t['id']
    labels = ', '.join(l['title'] for l in (t.get('labels') or []))
    print(f'  Task #{tid} ({labels}): {t[\"title\"]}')
    try:
        req = urllib.request.Request(
            '${VIKUNJA_URL}/api/v1/tasks/' + str(tid) + '/comments',
            headers={'Authorization': 'Bearer ${VIKUNJA_TOKEN}'}
        )
        resp = urllib.request.urlopen(req, timeout=5)
        comments = json.loads(resp.read())
        if comments:
            latest = comments[-1].get('comment', '')[:120]
            print(f'    Last: {latest}')
        else:
            print(f'    No comments yet')
    except Exception:
        print(f'    (comments unavailable)')
" 2>/dev/null
  fi
else
  echo "  FAIL  Vikunja API unreachable"
fi

# --- Machine Status ---
check_machine() {
  local host="$1" label="$2"
  echo ""
  echo "[$label]"

  if ! ssh -o ConnectTimeout=3 "$host" 'true' 2>/dev/null; then
    echo "  FAIL  Unreachable via SSH"
    return
  fi

  # Uptime
  local uptime
  uptime=$(ssh "$host" 'uptime' 2>/dev/null)
  echo "  OK  SSH: $uptime"

  # Tunnel
  local tunnel_check
  tunnel_check=$(ssh "$host" 'curl -sf http://localhost:3456/api/v1/info >/dev/null 2>&1 && echo OK || echo FAIL' 2>/dev/null)
  if [[ "$tunnel_check" == "OK" ]]; then
    echo "  OK  Vikunja tunnel active"
  else
    echo "  FAIL  Vikunja tunnel DOWN"
  fi

  # Agents
  echo "  --- Agents ---"
  local agents
  agents=$(ssh "$host" 'launchctl list 2>/dev/null | grep "com.axinova.agent-"' 2>/dev/null)
  if [[ -n "$agents" ]]; then
    while IFS= read -r line; do
      local pid status name
      pid=$(echo "$line" | awk '{print $1}')
      status=$(echo "$line" | awk '{print $2}')
      name=$(echo "$line" | awk '{print $3}' | sed 's/com.axinova.//')

      # Log filename matches the plist label without com.axinova. prefix
      local last_log
      last_log=$(ssh "$host" "tail -1 ~/logs/${name}-stdout.log 2>/dev/null" 2>/dev/null)

      if [[ "$pid" != "-" && "$status" == "0" ]]; then
        echo "  OK  $name (PID $pid)"
        if [[ -n "$last_log" ]]; then
          echo "       Last: $last_log"
        fi
      elif [[ "$pid" == "-" ]]; then
        echo "  FAIL  $name NOT RUNNING (exit $status)"
      else
        echo "  WARN  $name (PID $pid, exit $status)"
      fi
    done <<< "$agents"
  else
    echo "  WARN  No agents loaded"
  fi

  # Ollama
  if [[ "$label" == *"M2"* ]]; then
    echo "  --- Ollama ---"
    local models
    models=$(ssh "$host" 'curl -sf http://localhost:11434/api/tags 2>/dev/null | python3 -c "import sys,json; print(\", \".join(m[\"name\"] for m in json.load(sys.stdin)[\"models\"]))" 2>/dev/null')
    if [[ -n "$models" ]]; then
      echo "  OK  Models: $models"
    else
      echo "  FAIL  Ollama not responding"
    fi
  fi

  # Ollama tunnel (M4 only)
  if [[ "$label" == *"M4"* ]]; then
    echo "  --- Ollama Tunnel ---"
    local ollama_tunnel
    ollama_tunnel=$(ssh "$host" 'curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo OK || echo FAIL' 2>/dev/null)
    if [[ "$ollama_tunnel" == "OK" ]]; then
      echo "  OK  Ollama reachable via tunnel (localhost:11434)"
    else
      echo "  FAIL  Ollama tunnel not active"
    fi
  fi

  # Secrets check (env files exist, no API keys in plists)
  echo "  --- Secrets ---"
  local moonshot_env
  moonshot_env=$(ssh "$host" 'test -f ~/.config/axinova/moonshot.env && echo OK || echo MISSING' 2>/dev/null)
  echo "  ${moonshot_env}  moonshot.env"
  local discord_env
  discord_env=$(ssh "$host" 'test -f ~/.config/axinova/discord-webhooks.env && echo OK || echo MISSING' 2>/dev/null)
  echo "  ${discord_env}  discord-webhooks.env"

  # Disk
  local disk
  disk=$(ssh "$host" "df -h / | tail -1 | awk '{print \$4 \" free / \" \$2 \" total (\" \$5 \" used)\"}'" 2>/dev/null)
  echo "  Disk: $disk"
}

check_machine "$M4_HOST" "M4 Mac Mini (agent01) — backend-sde, frontend-sde"
check_machine "$M2_HOST" "M2 Pro Mac Mini (focusagent02) — devops, qa, tech-writer"

# --- Thunderbolt ---
echo ""
echo "[Thunderbolt Bridge]"
if ssh -o ConnectTimeout=3 "$M4_HOST" 'ping -c1 -W1 10.10.10.1 >/dev/null 2>&1' 2>/dev/null; then
  echo "  OK  M4 (10.10.10.2) <-> M2 Pro (10.10.10.1)"
  if ssh "$M4_HOST" 'curl -sf http://10.10.10.1:11434/api/tags >/dev/null 2>&1' 2>/dev/null; then
    echo "  OK  Ollama reachable via Thunderbolt"
  fi
else
  echo "  WARN  Not connected"
fi

# --- VPN ---
echo ""
echo "[VPN]"
if ping -c 1 -W 2 10.66.66.1 >/dev/null 2>&1; then
  echo "  OK  AmneziaVPN connected (10.66.66.1)"
else
  echo "  WARN  VPN not connected (non-blocking for LAN)"
fi

# --- LLM Models ---
echo ""
echo "[LLM Model Chain]"
echo "  1. Codex CLI (ChatGPT auth) — primary coding, built-in file tools"
echo "  2. Kimi K2.5 (Moonshot API) — cloud fallback, unified diff protocol"
echo "  3. Ollama (local)           — simple tasks, zero cloud cost"
echo "  Simple tasks (docs/lint/format) → Ollama directly"

echo ""
echo "==========================================="
echo "Quick commands:"
echo "  Logs:    ssh agent01@192.168.3.6 'tail -20 ~/logs/agent-backend-sde-stdout.log'"
echo "  Restart: ssh agent01@192.168.3.6 'launchctl kickstart -k gui/\$(id -u)/com.axinova.agent-backend-sde'"
echo "  All:     ssh agent01@192.168.3.6 'launchctl list | grep axinova'"
echo "  Kimi:    curl -sf api.moonshot.cn/v1/models -H 'Authorization: Bearer \$MOONSHOT_API_KEY' | jq"
echo "==========================================="
