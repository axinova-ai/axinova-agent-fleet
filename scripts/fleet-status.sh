#!/usr/bin/env bash
set -euo pipefail

# Show status of both agents

echo "==> Axinova Agent Fleet Status"
echo ""

# Check Agent1 (M4 Mac Mini)
echo "Agent1 (M4 Mac mini - Delivery):"
if ping -c 1 -W 1 192.168.3.6 &>/dev/null; then
  echo "  ✅ LAN reachable (192.168.3.6)"

  # Try SSH uptime
  if UPTIME=$(ssh -o ConnectTimeout=5 agent01@192.168.3.6 uptime 2>/dev/null); then
    echo "  ✅ SSH accessible"
    echo "     $UPTIME"

    # Check Docker
    if ssh agent01@192.168.3.6 "docker ps &>/dev/null" 2>/dev/null; then
      echo "  ✅ Docker running"
    else
      echo "  ⚠️  Docker not running"
    fi

    # Check agent daemons
    AGENTS=$(ssh agent01@192.168.3.6 "launchctl list 2>/dev/null | grep axinova || echo 'none'" 2>/dev/null)
    echo "  🤖 Agents: $AGENTS"

    # Check disk space
    DISK=$(ssh agent01@192.168.3.6 "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null)
    echo "  💾 Disk usage: $DISK"
  else
    echo "  ❌ SSH failed"
  fi
else
  echo "  ❌ Unreachable (check power, network)"
fi

echo ""

# Check Agent2 (M2 Pro Mac Mini)
echo "Agent2 (M2 Pro Mac mini - LLM + DevOps/QA):"
if ping -c 1 -W 1 192.168.3.5 &>/dev/null; then
  echo "  ✅ LAN reachable (192.168.3.5)"

  if UPTIME=$(ssh -o ConnectTimeout=5 focusagent02@192.168.3.5 uptime 2>/dev/null); then
    echo "  ✅ SSH accessible"
    echo "     $UPTIME"

    # Check Ollama (Agent2 speciality)
    if ssh focusagent02@192.168.3.5 "curl -sf http://localhost:11434/api/tags &>/dev/null" 2>/dev/null; then
      MODELS=$(ssh focusagent02@192.168.3.5 "curl -sf http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null | tr '\n' ', '" 2>/dev/null)
      echo "  ✅ Ollama running (models: ${MODELS%, })"
    else
      echo "  ⚠️  Ollama not running"
    fi

    # Check agent daemons
    AGENTS=$(ssh focusagent02@192.168.3.5 "launchctl list 2>/dev/null | grep axinova || echo 'none'" 2>/dev/null)
    echo "  🤖 Agents: $AGENTS"

    DISK=$(ssh focusagent02@192.168.3.5 "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null)
    echo "  💾 Disk usage: $DISK"
  else
    echo "  ❌ SSH failed"
  fi
else
  echo "  ❌ Unreachable (check power, network)"
fi

echo ""

# Check Thunderbolt Bridge
echo "Thunderbolt Bridge (M4 ↔ M2 Pro):"
if ssh -o ConnectTimeout=3 agent01@192.168.3.6 "ping -c 1 -W 1 10.10.10.1 &>/dev/null" 2>/dev/null; then
  echo "  ✅ M4 → M2 Pro (10.10.10.1) reachable"
  # Check Ollama over Thunderbolt
  if ssh agent01@192.168.3.6 "curl -sf http://10.10.10.1:11434/api/tags &>/dev/null" 2>/dev/null; then
    echo "  ✅ Ollama accessible via Thunderbolt"
  else
    echo "  ⚠️  Ollama not accessible via Thunderbolt"
  fi
else
  echo "  ⚠️  Thunderbolt not configured or cable not connected"
fi

echo ""

# Check VPN server
echo "VPN Server (Aliyun Singapore):"
if ping -c 1 -W 2 10.66.66.1 &>/dev/null; then
  echo "  ✅ Reachable (10.66.66.1)"
else
  echo "  ⚠️  VPN not connected (non-blocking for LAN operation)"
fi

echo ""

# Check RustDesk
echo "RustDesk (Remote Desktop):"
if ssh -o ConnectTimeout=3 agent01@192.168.3.6 "pgrep -x RustDesk &>/dev/null" 2>/dev/null; then
  echo "  ✅ Agent1: RustDesk running"
else
  echo "  ⚠️  Agent1: RustDesk not running"
fi
if ssh -o ConnectTimeout=3 focusagent02@192.168.3.5 "pgrep -x RustDesk &>/dev/null" 2>/dev/null; then
  echo "  ✅ Agent2: RustDesk running"
else
  echo "  ⚠️  Agent2: RustDesk not running"
fi

echo ""
echo "==> Summary"
echo "Agent logs: ssh agent01@192.168.3.6 'ls ~/logs/'"
echo "M2 Pro logs: ssh focusagent02@192.168.3.5 'ls ~/logs/'"
echo "Git activity: ssh agent01@192.168.3.6 'cd ~/workspace/axinova-home-go && git log --author=agent --since=\"1 day ago\"'"
