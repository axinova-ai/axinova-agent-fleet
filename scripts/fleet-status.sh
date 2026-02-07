#!/usr/bin/env bash
set -euo pipefail

# Show status of both agents

echo "==> Axinova Agent Fleet Status"
echo ""

# Check Agent1
echo "Agent1 (M4 Mac mini - Delivery):"
if ping -c 1 -W 1 10.100.0.10 &>/dev/null; then
  echo "  ✅ VPN reachable (10.100.0.10)"

  # Try SSH uptime
  if UPTIME=$(ssh -o ConnectTimeout=5 axinova-agent@10.100.0.10 uptime 2>/dev/null); then
    echo "  ✅ SSH accessible"
    echo "     $UPTIME"

    # Check Docker
    if ssh axinova-agent@10.100.0.10 "docker ps &>/dev/null" 2>/dev/null; then
      echo "  ✅ Docker running"
    else
      echo "  ⚠️  Docker not running"
    fi

    # Check disk space
    DISK=$(ssh axinova-agent@10.100.0.10 "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null)
    echo "  💾 Disk usage: $DISK"
  else
    echo "  ❌ SSH failed"
  fi
elif ping -c 1 -W 1 m4-mini.local &>/dev/null; then
  echo "  ✅ LAN reachable (m4-mini.local)"
  echo "  ⚠️  VPN not connected"
else
  echo "  ❌ Unreachable (check power, network)"
fi

echo ""

# Check Agent2
echo "Agent2 (M2 Pro Mac mini - Learning):"
if ping -c 1 -W 1 10.100.0.11 &>/dev/null; then
  echo "  ✅ VPN reachable (10.100.0.11)"

  if UPTIME=$(ssh -o ConnectTimeout=5 axinova-agent@10.100.0.11 uptime 2>/dev/null); then
    echo "  ✅ SSH accessible"
    echo "     $UPTIME"

    # Check Ollama (Agent2 speciality)
    if ssh axinova-agent@10.100.0.11 "curl -sf http://localhost:11434/api/tags &>/dev/null" 2>/dev/null; then
      echo "  ✅ Ollama running"
    else
      echo "  ⚠️  Ollama not running"
    fi

    DISK=$(ssh axinova-agent@10.100.0.11 "df -h / | tail -1 | awk '{print \$5}'" 2>/dev/null)
    echo "  💾 Disk usage: $DISK"
  else
    echo "  ❌ SSH failed"
  fi
elif ping -c 1 -W 1 m2-mini.local &>/dev/null; then
  echo "  ✅ LAN reachable (m2-mini.local)"
  echo "  ⚠️  VPN not connected"
else
  echo "  ❌ Unreachable (check power, network)"
fi

echo ""

# Check VPN server
echo "VPN Server (Aliyun Singapore):"
if ping -c 1 -W 2 10.100.0.1 &>/dev/null; then
  echo "  ✅ Reachable (10.100.0.1)"
else
  echo "  ❌ VPN not connected or server down"
  echo "     Connect: cd ~/axinova/axinova-agent-fleet/bootstrap/vpn && ./connect-sg.sh"
fi

echo ""
echo "==> Summary"
echo "For detailed logs, SSH to agents and check:"
echo "  - Agent runtime logs: ~/workspace/agent-fleet/logs/"
echo "  - CI history: ~/workspace/agent-fleet/ci-history/"
echo "  - Git activity: cd ~/workspace/axinova-home-go && git log --author=agent --since='1 day ago'"
