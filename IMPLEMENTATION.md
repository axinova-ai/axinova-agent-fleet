# Agent Fleet Implementation Guide

Step-by-step guide to deploy the agent fleet on two Mac minis.

## Prerequisites

- Two Mac minis (M4 16GB + M2 Pro 16GB)
- GitHub organization admin access (axinova-ai)
- OpenAI account (for Codex CLI auth)
- Moonshot API key (for Kimi K2.5 via OpenClaw + agent-launcher)
- MCP tokens (Portainer, Grafana, SilverBullet, Vikunja)
- AmneziaWG configs already generated (in `vpn-distribution/configs/macos/`)

## Timeline

**Total: ~14 hours (2-3 days)**

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 0: Pre-flight | 30 min | None |
| Phase 1: Bootstrap | 2 hours | Phase 0 |
| Phase 2: VPN + Thunderbolt | 1 hour | Phase 1 |
| Phase 2.5: Multi-model agent runtime | 2 hours | Phase 2 |
| Phase 3: Agent deployment | 2 hours | Phase 2.5 |
| Phase 3.5: OpenClaw multi-agent | 2 hours | Phase 3 |
| Phase 4: GitHub/CI updates | 1 hour | Phase 0 |
| Phase 5: E2E test | 2 hours | All |

---

## Phase 0: Pre-flight (from your laptop)

### 0.1 Create GitHub fine-grained PAT

Using your existing GitHub account (`harryxiaxia`):

1. Go to https://github.com/settings/personal-access-tokens/new
2. Token name: `Agent Fleet - M4` (create a second one for M2Pro later)
3. Expiration: 1 year
4. Resource owner: `axinova-ai`
5. Repository access: All repositories (or select `axinova-*` repos)
6. Permissions: `contents:write`, `pull_requests:write`, `issues:write`, `metadata:read`
7. Store token in 1Password vault "Axinova"

### 0.2 Gather credentials

```bash
# From 1Password
op item get "Anthropic API Key" --fields password
op item get "Portainer API Token" --fields password
op item get "Grafana API Token" --fields password
op item get "SilverBullet API Token" --fields password
op item get "Vikunja API Token" --fields password
op item get "Moonshot API Key" --fields password
```

### 0.3 Create Discord bot

1. Go to https://discord.com/developers/applications → New Application → "Axinova Fleet"
2. Bot tab → Add Bot → copy token → save to 1Password
3. Enable: Message Content Intent, Server Members Intent
4. OAuth2 → URL Generator → scopes: `bot` → permissions: Send Messages, Embed Links, Read Message History
5. Use generated URL to invite bot to your Discord server
6. Create channels: `#agent-tasks`, `#agent-prs`, `#agent-alerts`, `#agent-logs`

### 0.4 Set up Vikunja project

1. Go to `vikunja.axinova-internal.xyz`
2. Create project "Agent Fleet"
3. Add labels: `backend-sde`, `frontend-sde`, `devops`, `qa`, `docs`, `urgent`, `blocked`
4. Set up Kanban views: Open | In Progress | Review | Done

---

## Phase 1: Mac Mini Bootstrap

Run on each Mac mini (M4 first, then M2 Pro).

### 1.1 Physical setup

1. Power on, complete macOS Setup Assistant
2. Create admin user `weixia`
3. System Settings → General → Sharing → Remote Login = ON
4. System Settings → General → Sharing → Screen Sharing = ON
5. Note IP address

### 1.2 Run bootstrap

```bash
# From your laptop
ssh weixia@<mac-mini-ip>

# Clone the repo
git clone https://github.com/axinova-ai/axinova-agent-fleet.git ~/workspace/axinova-agent-fleet

# Run bootstrap
cd ~/workspace/axinova-agent-fleet/bootstrap/mac
./setup-macos.sh
```

This installs: Homebrew, Go, Node, Docker, gh CLI, Codex CLI, Claude Code, tmux, jq, AmneziaWG.

### 1.3 Configure Codex CLI (Agent Runtime)

```bash
# Codex CLI first-run auth (OpenAI login)
codex  # Follow prompts to authenticate with OpenAI
```

### 1.4 Configure MCP

```bash
# Edit the config with actual tokens
cp ~/workspace/axinova-agent-fleet/integrations/mcp/agent-mcp-config.json ~/.claude/settings.json

# Replace ${PORTAINER_TOKEN}, ${GRAFANA_TOKEN}, etc. with actual values
# Also build the MCP server binary:
cd ~/workspace/axinova-mcp-server-go && make build
```

### 1.5 Configure GitHub

```bash
gh auth login --with-token <<< "<PAT from 1Password>"
# Git identity is set by setup-macos.sh automatically:
#   M4:     "Axinova M4 Agent" <m4@axinova.local>
#   M2 Pro: "Axinova M2Pro Agent" <m2pro@axinova.local>
```

### 1.6 Clone all repos

```bash
cd ~/workspace
for repo in axinova-home-go axinova-home-web axinova-miniapp-builder-go axinova-miniapp-builder-web \
  axinova-ai-social-publisher-go axinova-ai-social-publisher-web axinova-trading-agent-go \
  axinova-trading-agent-web axinova-ai-lab-go axinova-deploy axinova-mcp-server-go; do
  git clone git@github.com:axinova-ai/$repo.git
done
```

### 1.7 Verify

```bash
codex --version                           # Codex CLI installed
go version                                # Go 1.24+
node --version                            # Node 22+
gh auth status                            # Logged in as harryxiaxia
curl -sf -H "Authorization: Bearer $APP_VIKUNJA__TOKEN" \
  "$APP_VIKUNJA__URL/api/v1/projects" | jq '.[].title'  # Vikunja API works
```

---

## Phase 2: AmneziaWG VPN + Thunderbolt

### 2.1 VPN setup (each machine)

```bash
cd ~/workspace/axinova-agent-fleet/bootstrap/vpn
./amneziawg-setup.sh
```

This imports the pre-generated config (with correct AWG obfuscation params) into the AmneziaWG app.

- M4 gets IP 10.66.66.3
- M2 Pro gets IP 10.66.66.2

Enable "Connect on login" in the AmneziaWG app preferences.

### 2.2 Thunderbolt Bridge

1. Connect Thunderbolt cable between M4 and M2 Pro
2. On M4: System Settings → Network → Thunderbolt Bridge → Manual → IP: `169.254.100.1`, Subnet: `255.255.255.0`
3. On M2 Pro: Same but IP: `169.254.100.2`

### 2.3 Verify

```bash
ping 10.66.66.1          # VPN server (Singapore)
ping 10.66.66.2          # M2 Pro via VPN (or .3 for M4)
ping 169.254.100.1       # M4 via Thunderbolt (or .2 for M2 Pro)
curl -k https://vikunja.axinova-internal.xyz/api/v1/info
```

---

## Phase 2.5: Multi-Model Agent Runtime

### 2.5.1 Deploy secrets (both machines)

```bash
# On both Mac Minis:
mkdir -p ~/.config/axinova && chmod 700 ~/.config/axinova

# Moonshot API key (for Kimi K2.5)
echo 'MOONSHOT_API_KEY=sk-...' > ~/.config/axinova/moonshot.env
chmod 600 ~/.config/axinova/moonshot.env
```

### 2.5.2 Deploy updated agent-launcher.sh

```bash
# From your laptop to both machines
scp scripts/agent-launcher.sh agent01@192.168.3.6:~/workspace/axinova-agent-fleet/scripts/
scp scripts/agent-launcher.sh focusagent02@192.168.3.5:~/workspace/axinova-agent-fleet/scripts/
```

### 2.5.3 Deploy Ollama tunnel (M4 only)

```bash
# M4 needs Ollama tunnel to reach M2 Pro's Ollama via Thunderbolt
scp launchd/com.axinova.ollama-tunnel.plist agent01@192.168.3.6:~/Library/LaunchAgents/
ssh agent01@192.168.3.6 'launchctl load ~/Library/LaunchAgents/com.axinova.ollama-tunnel.plist'
```

### 2.5.4 Test multi-model execution

```bash
# On M4, test Kimi K2.5 API
source ~/.config/axinova/moonshot.env
curl -sf https://api.moonshot.cn/v1/models \
  -H "Authorization: Bearer $MOONSHOT_API_KEY" | jq '.data[].id'

# On M4, test Ollama via tunnel
curl -sf http://localhost:11434/api/tags | jq '.models[].name'

# On M2 Pro, test Ollama directly
curl -sf http://localhost:11434/api/tags | jq '.models[].name'
```

### 2.5.5 Benchmark local models (optional)

```bash
# On M2 Pro
cd ~/workspace/axinova-agent-fleet
./scripts/benchmark-ollama.sh
```

---

## Phase 3: Agent Deployment

### 3.1 Test agent launcher manually

```bash
# On M4, as agent01
cd ~/workspace/axinova-agent-fleet

# Test with a backend task (will poll, select model, execute)
./scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go 60
```

Create a test task in Vikunja labeled `backend-sde` and verify:
- Agent picks up the task
- Vikunja comments appear (CLAIMED, STARTED, COMPLETED/BLOCKED)
- Discord gets notified with rich embed
- PR is created (if model produces valid changes)

### 3.2 Install launchd daemons

**On M4 Mac Mini:**
```bash
mkdir -p ~/Library/LaunchAgents ~/logs
cp launchd/com.axinova.agent-backend-sde.plist ~/Library/LaunchAgents/
cp launchd/com.axinova.agent-frontend-sde.plist ~/Library/LaunchAgents/
cp launchd/com.axinova.ollama-tunnel.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-backend-sde.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-frontend-sde.plist
launchctl load ~/Library/LaunchAgents/com.axinova.ollama-tunnel.plist
```

**On M2 Pro Mac Mini:**
```bash
mkdir -p ~/Library/LaunchAgents ~/logs
cp launchd/com.axinova.agent-devops.plist ~/Library/LaunchAgents/
cp launchd/com.axinova.agent-qa.plist ~/Library/LaunchAgents/
cp launchd/com.axinova.agent-tech-writer.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-devops.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-qa.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-tech-writer.plist
```

### 3.3 Verify

```bash
# Check agents are running
launchctl list | grep axinova

# Check logs
tail -f ~/logs/agent-backend-sde-stdout.log

# Check fleet status (from laptop)
./scripts/fleet-status.sh
```

---

## Phase 3.5: OpenClaw Multi-Agent + Discord

### 3.5.1 Install OpenClaw on M4

```bash
ssh agent01@192.168.3.6
npm install -g openclaw@latest
```

### 3.5.2 Run setup

```bash
cd ~/workspace/axinova-agent-fleet/openclaw
./setup.sh
```

During onboarding, provide:
- Discord bot token (from Phase 0.3)
- Moonshot API key (for Kimi K2.5)
- Discord server ID, channel IDs

### 3.5.3 Start OpenClaw daemon

```bash
cp launchd/com.axinova.openclaw.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.openclaw.plist
```

### 3.5.4 Verify

Send messages in Discord:
- `#agent-tasks`: "Add a /health endpoint to miniapp-builder-go" → should create Vikunja task
- `#agent-tasks`: `/status` → should show fleet status
- `#agent-tasks`: `/assign devops Update Docker Compose for staging` → should create labeled task

---

## Phase 4: GitHub & CI/CD Updates

### 4.1 Exclude agent branches from CI

For each repo with deploy workflows, add to branch filters:
```yaml
branches:
  - '!agent/**'
```

### 4.2 Branch protection

For all repos, configure `main` branch:
- Require PR before merging
- Require 1 approval
- Require CI status checks to pass

---

## Phase 5: End-to-End Tests

### Test 1: Direct Vikunja → Kimi K2.5
1. Create task in Vikunja project 13 with label `backend-sde`
2. Verify: agent claims → Vikunja comments (CLAIMED, STARTED) → Kimi K2.5 generates unified diff → `git apply` → PR → COMPLETED comment → Discord notified

### Test 2: Discord → OpenClaw → Agent
1. Post in Discord #agent-tasks: "Add a /v1/templates endpoint to miniapp-builder-go"
2. Verify: OpenClaw creates Vikunja task → agent picks up → full lifecycle

### Test 3: Simple task via Ollama
1. Create task with label `docs`: "Update README with deployment instructions"
2. Verify: routes to Ollama → completes locally → no cloud API calls

### Test 4: Codex CLI path
1. Create coding task → agent tries Codex CLI first
2. Verify: if ChatGPT auth works, native execution → PR

**Success criteria:**
- Discord to PR: under 15 min
- PR follows code conventions from CLAUDE.md
- Full audit trail: Vikunja comments → Discord notifications → GitHub PR
- No API keys in any plist file (all in `~/.config/axinova/*.env`)
- No wasted GitHub Actions minutes (agent branches excluded)

---

## Troubleshooting

### Agent not picking up tasks
1. Check logs: `tail -f ~/logs/agent-<role>-stdout.log`
2. Verify Vikunja API: `curl -sf -H "Authorization: Bearer $APP_VIKUNJA__TOKEN" "$APP_VIKUNJA__URL/api/v1/projects" | jq '.[].title'`
3. Check launchd status: `launchctl list | grep axinova`
4. Restart agent: `launchctl kickstart -k gui/$(id -u)/com.axinova.agent-<role>`

### LLM model failures
1. Check Kimi API: `source ~/.config/axinova/moonshot.env && curl -sf https://api.moonshot.cn/v1/models -H "Authorization: Bearer $MOONSHOT_API_KEY" | jq '.data[].id'`
2. Check Ollama: `curl -sf http://localhost:11434/api/tags | jq '.models[].name'`
3. Check Codex CLI: `codex --version` (if ChatGPT auth expired, re-run `codex` for OAuth)
4. Fallback chain: Codex → Kimi → Ollama (check logs for which model was used)

### Vikunja comments not appearing
1. Verify token has write access: `curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"comment":"test"}' "http://localhost:3456/api/v1/tasks/<id>/comments"`
2. Check agent-launcher.sh logs for `add_task_comment` errors

### VPN not connecting
1. Check AmneziaWG app status
2. Verify config has correct obfuscation params
3. Test: `ping 10.66.66.1`
4. Check Aliyun console firewall (UDP 54321 must be open)

### MCP tools not working
1. Verify binary exists: `ls ~/workspace/axinova-mcp-server-go/bin/axinova-mcp-server`
2. Check tokens in `~/.claude/settings.json`
3. Test directly: `curl -sf -H "Authorization: Bearer $APP_VIKUNJA__TOKEN" "$APP_VIKUNJA__URL/api/v1/projects" | jq`

### PR creation fails
1. Check GitHub auth: `gh auth status`
2. Verify bot has repo access
3. Check for branch conflicts: `git status`

### Unified diff fails to apply
1. Check logs for `git apply` error output
2. Common causes: wrong file paths, insufficient context lines, file already modified
3. The agent will comment `[BLOCKED]` on the Vikunja task with the error
4. Try running the model again or manually apply the suggested changes
