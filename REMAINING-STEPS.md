# Remaining Steps to Complete Agent Fleet

## Step 1: Expand GitHub PAT Scope

The fine-grained PAT `axinova-gitops-agent` currently only has access to `axinova-agent-fleet` and `axinova-mcp-server-go`.

1. Go to https://github.com/settings/personal-access-tokens
2. Edit the `axinova-gitops-agent` token
3. Under "Repository access", change to "All repositories" (or add all `axinova-ai/*` repos)
4. Save

Then clone remaining repos on both machines:

```bash
# On M4 (agent01@192.168.3.6)
ssh agent01@192.168.3.6
source ~/.zprofile
cd ~/workspace
for repo in axinova-home-go axinova-ai-lab-go axinova-miniapp-builder-go \
  axinova-ai-social-publisher-go axinova-trading-agent-go axinova-home-web \
  axinova-miniapp-builder-web axinova-ai-social-publisher-web \
  axinova-trading-agent-web axinova-deploy; do
  git clone https://github.com/axinova-ai/$repo.git
done

# Repeat on M2 Pro (focusagent02@192.168.3.5) with same commands
```

## Step 2: Codex CLI Auth (OpenAI)

Run `codex` interactively on both machines to complete first-run auth:

```bash
# On M4
ssh agent01@192.168.3.6
source ~/.zprofile
cd ~/workspace/axinova-home-go
codex  # First run will prompt for OpenAI auth (ChatGPT login or API key)

# On M2 Pro
ssh focusagent02@192.168.3.5
source ~/.zprofile
cd ~/workspace/axinova-home-go
codex
```

## Step 3: Moonshot (Kimi) API Key

Get API key from https://platform.moonshot.cn/

Then set it on M4 where OpenClaw runs:

```bash
ssh agent01@192.168.3.6
mkdir -p ~/.config/axinova
echo 'export MOONSHOT_API_KEY="sk-your-key-here"' >> ~/.config/axinova/moonshot.env
```

OpenClaw's `openclaw.json` already has `${MOONSHOT_API_KEY}` placeholder configured.

## Step 4: Thunderbolt Bridge (needs physical cable)

Connect Thunderbolt cable between M4 and M2 Pro, then configure static IPs:

**On M4** (System Settings → Network → Thunderbolt Bridge):
- IPv4: Manual, IP: `10.10.10.2`, Subnet: `255.255.255.0`

**On M2 Pro** (System Settings → Network → Thunderbolt Bridge):
- IPv4: Manual, IP: `10.10.10.1`, Subnet: `255.255.255.0`

Verify:

```bash
# From M4
ssh agent01@192.168.3.6
ping -c 1 10.10.10.1
curl -sf http://10.10.10.1:11434/api/tags | jq ".models[].name"
```

## Step 5: Set Up Vikunja "Agent Fleet" Project

Create project with labels for agent roles:
- `backend-sde` - Go backend tasks
- `frontend-sde` - Vue frontend tasks
- `devops` - Infrastructure/deployment tasks
- `qa` - Testing tasks
- `tech-writer` - Documentation tasks

Also set the Vikunja token as env var for `agent-launcher.sh`:

```bash
# On both machines
echo 'export APP_VIKUNJA__URL="https://vikunja.axinova-internal.xyz"' >> ~/.config/axinova/vikunja.env
echo 'export APP_VIKUNJA__TOKEN="tk_c92243afb12553b93ee222f1f6c242fb0b746800"' >> ~/.config/axinova/vikunja.env
```

Update launchd plists to source this env (or add to plist EnvironmentVariables).

## Step 6: Deploy Agent Daemons

Once Codex auth and repos are cloned:

```bash
# On M4 - backend-sde + frontend-sde agents
ssh agent01@192.168.3.6
mkdir -p ~/Library/LaunchAgents ~/logs
cp ~/workspace/axinova-agent-fleet/launchd/com.axinova.agent-backend-sde.plist ~/Library/LaunchAgents/
cp ~/workspace/axinova-agent-fleet/launchd/com.axinova.agent-frontend-sde.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-backend-sde.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-frontend-sde.plist

# On M2 Pro - devops + qa + tech-writer agents
ssh focusagent02@192.168.3.5
mkdir -p ~/Library/LaunchAgents ~/logs
cp ~/workspace/axinova-agent-fleet/launchd/com.axinova.agent-devops.plist ~/Library/LaunchAgents/
cp ~/workspace/axinova-agent-fleet/launchd/com.axinova.agent-qa.plist ~/Library/LaunchAgents/
cp ~/workspace/axinova-agent-fleet/launchd/com.axinova.agent-tech-writer.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.axinova.agent-devops.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-qa.plist
launchctl load ~/Library/LaunchAgents/com.axinova.agent-tech-writer.plist
```

## Step 7: Test Agent Runtime

```bash
# Quick manual test on M4
ssh agent01@192.168.3.6
source ~/.zprofile
cd ~/workspace/axinova-home-go
~/workspace/axinova-agent-fleet/scripts/agent-launcher.sh backend-sde ~/workspace/axinova-home-go 60
# Expected: polls Vikunja, finds no tasks, exits after 60s
```

## Step 8: OpenClaw + Discord

```bash
ssh agent01@192.168.3.6
source ~/.config/axinova/moonshot.env
cd ~/workspace/axinova-agent-fleet/openclaw
./setup.sh
```

## Step 9: End-to-End Test

1. Create a Vikunja task with label `backend-sde`
2. Agent on M4 picks it up via `agent-launcher.sh`
3. Codex CLI implements changes, commits
4. Script pushes branch, creates PR via `gh`
5. You review PR with Claude Code, merge
6. Discord notification in #agent-prs

---

## Architecture Summary

```
Discord → OpenClaw (Kimi K2.5) → Vikunja task
                                       ↓
                              agent-launcher.sh polls
                                       ↓
                              Codex CLI (OpenAI native)
                                       ↓
                              git commit + push + gh pr create
                                       ↓
                              Human reviews with Claude Code → merge
```

## What's Already Done

- [x] Both machines bootstrapped (Homebrew, Go, Node, git, gh, etc.)
- [x] SSH keys generated on both machines
- [x] GitHub auth (`gh auth login`) on both
- [x] AmneziaVPN installed + connected on both
- [x] Ollama + Qwen 2.5 7B + Coder 7B on M2 Pro
- [x] MCP server built + config deployed on both
- [x] Codex CLI v0.106.0 installed on both
- [x] Claude Code v2.1.49 installed on both
- [x] `axinova-agent-fleet` + `axinova-mcp-server-go` cloned on both
- [x] Launchd plists updated for agent01/focusagent02
- [x] agent-launcher.sh rewritten for Codex CLI + direct Vikunja API
- [x] openclaw.json configured for Kimi K2.5 (API key placeholder)
