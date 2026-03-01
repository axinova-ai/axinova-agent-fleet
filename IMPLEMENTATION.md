# Agent Fleet Implementation Guide

Step-by-step guide to deploy the agent fleet on two Mac minis.

## Prerequisites

- Two Mac minis (M4 16GB + M2 Pro 16GB)
- GitHub organization admin access (axinova-ai)
- OpenAI account (for Codex CLI auth)
- Moonshot API key (for Kimi K2.5 via OpenClaw)
- MCP tokens (Portainer, Grafana, SilverBullet, Vikunja)
- AmneziaWG configs already generated (in `vpn-distribution/configs/macos/`)

## Timeline

**Total: ~12 hours (2 days)**

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 0: Pre-flight | 30 min | None |
| Phase 1: Bootstrap | 2 hours | Phase 0 |
| Phase 2: VPN + Thunderbolt | 1 hour | Phase 1 |
| Phase 3: Agent runtime | 3 hours | Phase 1, 2 |
| Phase 4: OpenClaw + Discord | 2 hours | Phase 3 |
| Phase 5: GitHub/CI updates | 1 hour | Phase 0 |
| Phase 6: E2E test | 2 hours | All |

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

## Phase 3: Agent Runtime

### 3.1 Test agent launcher manually

```bash
# On M4, as axinova-agent
cd ~/workspace/axinova-agent-fleet

# Test with a backend task
./scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go 60
```

Create a test task in Vikunja labeled `backend-sde` and verify the agent picks it up.

### 3.2 Install launchd daemons

**On M4 Mac Mini:**
```bash
mkdir -p ~/Library/LaunchAgents ~/logs
cp launchd/com.axinova.agent-backend-sde.plist ~/Library/LaunchAgents/
cp launchd/com.axinova.agent-frontend-sde.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-backend-sde.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-frontend-sde.plist
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
tail -f ~/logs/agent-backend-sde.log
```

---

## Phase 4: OpenClaw + Discord

### 4.1 Install on M4

```bash
cd ~/workspace/axinova-agent-fleet/openclaw
./setup.sh
```

### 4.2 Configure

During onboarding, select **Discord** as the messaging platform and provide:
- Discord bot token (from Phase 0.3)
- Moonshot API key (for Kimi K2.5)

### 4.3 Verify

Send a message in Discord `#agent-tasks` channel. The bot should respond and be able to create Vikunja tasks.

---

## Phase 5: GitHub & CI/CD Updates

### 5.1 Exclude agent branches from CI

For each repo with deploy workflows, add to branch filters:
```yaml
branches:
  - '!agent/**'
```

### 5.2 Branch protection

For all repos, configure `main` branch:
- Require PR before merging
- Require 1 approval
- Require CI status checks to pass

---

## Phase 6: End-to-End Test

1. Send via Discord: "Add a /v1/templates endpoint to miniapp-builder-go"
2. Verify: OpenClaw creates Vikunja task with `backend-sde` label
3. Verify: Backend SDE agent picks up task within 2 min
4. Verify: Agent creates branch, implements, tests, pushes, creates PR
5. Verify: Vikunja task updated, SilverBullet log entry
6. Review PR on GitHub, approve, merge
7. Verify: CI runs on merge, deployment triggers

**Success criteria:**
- Discord to PR: under 15 min
- PR follows Go conventions from CLAUDE.md
- No wasted GitHub Actions minutes
- Full audit trail: Vikunja → SilverBullet → GitHub PR → Discord notification

---

## Troubleshooting

### Agent not picking up tasks
1. Check logs: `tail -f ~/logs/agent-<role>.log`
2. Verify Vikunja API: `curl -sf -H "Authorization: Bearer $APP_VIKUNJA__TOKEN" "$APP_VIKUNJA__URL/api/v1/projects" | jq '.[].title'`
3. Check launchd status: `launchctl list | grep axinova`
4. Restart agent: `launchctl kickstart -k gui/$(id -u)/com.axinova.agent-<role>`

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
