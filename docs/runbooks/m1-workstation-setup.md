# M1 Workstation Setup Runbook

End-to-end guide for setting up the Mac Mini M1 (16GB/512GB) as a personal workstation
for remote access via Claude Code on iPhone. This machine is NOT an autonomous agent node —
it is a human-controlled workstation with full access to all Axinova repos and secrets.

---

## Machine Role

| Property | Value |
|----------|-------|
| Role | Personal workstation (not agent fleet) |
| Primary use | Claude Code remote sessions from iPhone |
| SSH alias | `workstation` |
| VPN IP | `10.66.66.4` (reserve in `clients.yml`) |
| Repos | All Axinova repos cloned to `~/workspace/` |
| Secret source | 1Password vault via `op` CLI |

---

## Step 1: macOS Initial Setup

1. Boot, complete Setup Assistant
2. **Sign in with Apple ID** (unlike fleet agents — you need iCloud, App Store)
3. Account name: your personal username (e.g. `weixia`)
4. System Settings → Software Update → install all pending updates
5. System Settings → General → Sharing → set hostname: `m1-workstation`

---

## Step 2: Install Core Tools

```bash
# Xcode CLI tools
xcode-select --install

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to ~/.zshrc (Apple Silicon path)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
source ~/.zshrc

# Core tools
brew install \
  git gh \
  go \
  jq curl \
  1password-cli \
  direnv

# Claude Code CLI (via Homebrew)
brew install --cask claude-code

# Codex CLI (for running agent tasks manually if needed)
npm install -g @openai/codex
```

---

## Step 3: 1Password — Secret Management

**Why 1Password:** Native `op inject` templates, SSH key agent with Touch ID, iOS app,
and zero secrets on disk. One account syncs to unlimited devices.

### 3a. Install and Sign In

1. Install 1Password from App Store (or `brew install --cask 1password`)
2. Sign in with your 1Password account
3. Enable CLI integration: **Settings → Developer → Connect with 1Password CLI**
4. Enable SSH agent: **Settings → Developer → Use the SSH agent**

### 3b. Add to `~/.zshrc`

```bash
# 1Password CLI biometric unlock
export OP_BIOMETRIC_UNLOCK_ENABLED=true

# direnv hook
eval "$(direnv hook zsh)"

# Source secrets for interactive shell (Touch ID once per session)
if command -v op &>/dev/null; then
  source <(op inject -i ~/.config/axinova/secrets.env.tpl 2>/dev/null) || true
fi
```

### 3c. SSH Agent via 1Password

Add to `~/.ssh/config` (create if missing):

```
Host *
    IdentityAgent "~/.1password/agent.sock"
```

Create the socket symlink:

```bash
mkdir -p ~/.1password
ln -sf ~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock \
    ~/.1password/agent.sock
```

SSH private keys live in 1Password, never on disk. Every git push / SSH connection
triggers a Touch ID confirmation.

### 3d. Create the Secrets Vault in 1Password

Create a vault named **Axinova** and add these items:

| Item Name | Type | Fields |
|-----------|------|--------|
| GitHub PAT | API Credential | `credential` |
| Moonshot Kimi API | API Credential | `credential` |
| Discord Webhook - fleet | Login | `url` |
| SilverBullet Token | Password | `password` |
| Vikunja Token | Password | `password` |
| Portainer Admin | Login | `username`, `password` |
| Grafana Admin | Login | `username`, `password` |
| SSH Key - fleet-agent | SSH Key | (import existing key) |
| OP Service Account - fleet | Password | `password` (for launchd daemons on M4/M2) |

### 3e. Create Template File

```bash
mkdir -p ~/.config/axinova
cat > ~/.config/axinova/secrets.env.tpl << 'EOF'
# 1Password secret references — safe to commit to dotfiles
GITHUB_PAT=op://Axinova/GitHub PAT/credential
MOONSHOT_API_KEY=op://Axinova/Moonshot Kimi API/credential
DISCORD_WEBHOOK_AXINOVA=op://Axinova/Discord Webhook - fleet/url
APP_SILVERBULLET__TOKEN=op://Axinova/SilverBullet Token/password
VIKUNJA_TOKEN=op://Axinova/Vikunja Token/password
EOF
chmod 600 ~/.config/axinova/secrets.env.tpl
```

### 3f. Generate Resolved Secrets File

```bash
op inject -i ~/.config/axinova/secrets.env.tpl \
          -o ~/.config/axinova/secrets.env
chmod 600 ~/.config/axinova/secrets.env
```

Run this command whenever secrets change in 1Password (or after rotation).

---

## Step 4: SSH Configuration and Fleet Access

### 4a. SSH Config (`~/.ssh/config`)

```
# M1 Workstation identity (via 1Password agent — no key file needed)
Host *
    IdentityAgent "~/.1password/agent.sock"
    ServerAliveInterval 60
    ServerAliveCountMax 3

# Agent fleet (via VPN)
Host agent01
    HostName 10.66.66.3
    User axinova-agent
    ForwardAgent yes

Host agent02
    HostName 10.66.66.2
    User axinova-agent
    ForwardAgent yes

# Agent fleet (via LAN — same network only)
Host agent01-lan
    HostName m4-mini.local
    User axinova-agent
    ForwardAgent yes

Host agent02-lan
    HostName m2-mini.local
    User axinova-agent
    ForwardAgent yes

# Vikunja SSH tunnel (for direct API access)
Host vikunja-tunnel
    HostName 10.66.66.2
    User axinova-agent
    LocalForward 3456 localhost:3456
    ForwardAgent yes
    ExitOnForwardFailure yes
```

### 4b. Add Workstation Public Key to Fleet Machines

After 1Password SSH agent is set up and your SSH key is stored there:

```bash
# Get your public key from 1Password
op read "op://Axinova/SSH Key - fleet-agent/public key"

# Copy to each fleet machine (run once each)
ssh-copy-id axinova-agent@m4-mini.local
ssh-copy-id axinova-agent@m2-mini.local

# Test
ssh agent01 'hostname && date'
ssh agent02 'hostname && date'
```

---

### 4c. SSH Key Strategy — Passphrase-Free for Non-Interactive Use

The M1 workstation uses **two separate SSH key files**:

| File | Passphrase | Used for |
|------|-----------|---------|
| `~/.ssh/id_ed25519` | **Yes** (protected) | Interactive sessions only — macOS Keychain unlocks via Touch ID |
| `~/.ssh/id_ed25519_tunnel` | **No** | All outbound SSH from automated/non-interactive contexts (Claude Code, launchd) |

**Why this matters:** Claude Code runs SSH commands in non-interactive subprocesses where `/dev/tty` is unavailable. A passphrase-protected key silently fails with `Permission denied (publickey)` — not a "wrong key" error, just a missing TTY for the passphrase prompt.

**SSH config must use `id_ed25519_tunnel` for all host entries:**

```
Host ax-sas-tools
  HostName 121.40.188.25
  User root
  IdentityFile ~/.ssh/id_ed25519_tunnel   # NOT id_ed25519
  IdentitiesOnly yes

Host sg-vpn
  HostName 8.222.187.10
  User root
  IdentityFile ~/.ssh/id_ed25519_tunnel   # NOT id_ed25519
  IdentitiesOnly yes

Host agent01
  HostName 192.168.3.6
  User agent01
  IdentityFile ~/.ssh/id_ed25519_tunnel
  IdentitiesOnly yes
  ForwardAgent yes
```

**Authorized keys:** `id_ed25519_tunnel.pub` (comment: `m1-workstation-tunnel`) must be added to `~/.ssh/authorized_keys` on every target server. As of 2026-03-13 it is present on: ax-sas-tools, sg-vpn, agent01, agent02.

**If you add a new server** and Claude Code can't SSH to it from this machine, check this first — add `id_ed25519_tunnel.pub` to that server's `authorized_keys`.

---

## Step 5: VPN Setup (AmneziaWG)

The M1 workstation needs VPN to reach fleet machines when not on home LAN.

### 5a. Reserve VPN IP

In `ansible/inventories/vpn/clients.yml`, add:

```yaml
m1-workstation:
  ansible_host: <LAN IP>
  vpn_ip: 10.66.66.4
  description: "M1 personal workstation"
```

### 5b. Generate and Deploy Config

From your MacBook Air (where Ansible runs):

```bash
cd ~/workspace/axinova-agent-fleet/ansible
./scripts/onboard-vpn-clients.sh m1-workstation
```

This generates `vpn-distribution/configs/m1-workstation.conf` with AmneziaWG obfuscation params.

### 5c. Import on M1

```bash
# Install AmneziaWG
brew install amneziawg  # or download from GitHub releases
# Import the generated config file into the AmneziaWG app
```

Verify: `ping 10.66.66.1`

---

## Step 6: Clone All Repos

```bash
mkdir -p ~/workspace
cd ~/workspace

# Fleet management
git clone git@github.com:axinova-ai/axinova-agent-fleet.git

# Backend services
git clone git@github.com:axinova-ai/axinova-home-go.git
git clone git@github.com:axinova-ai/axinova-ai-lab-go.git
git clone git@github.com:axinova-ai/axinova-miniapp-builder-go.git

# Frontend
git clone git@github.com:axinova-ai/axinova-miniapp-builder-web.git

# Infrastructure
git clone git@github.com:axinova-ai/axinova-deploy.git

# Set git identity
git config --global user.name "Wei Xia"
git config --global user.email "wei@axinova.ai"
git config --global core.editor "code --wait"  # or vim
```

---

## Step 7: Claude Code Remote Access (iPhone)

Claude Code supports remote access from any device via a browser-based interface.

### 7a. Enable Remote Access on M1

```bash
# Start Claude Code with remote tunnel enabled
claude --tunnel

# Or for persistent background tunnel (add to ~/.zshrc or launchd)
claude tunnel &
```

This prints a URL like `https://claude.ai/r/xxxx` — open on iPhone.

### 7b. Persistent Tunnel via launchd

Create `~/Library/LaunchAgents/com.axinova.claude-tunnel.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.axinova.claude-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/claude</string>
        <string>--tunnel</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/weixia</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/claude-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-tunnel.err</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.axinova.claude-tunnel.plist
```

Get the tunnel URL: `cat /tmp/claude-tunnel.log | grep https://`

### 7c. Secrets Available in Claude Code Sessions

Claude Code reads environment variables from the shell that launches it.
The `~/.zshrc` `op inject` line (Step 3b) makes secrets available automatically.

For the launchd plist, add the secret loading wrapper:

```xml
<key>ProgramArguments</key>
<array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>source ~/.zshrc && claude --tunnel</string>
</array>
```

---

## Step 8: Headless Power Settings

```bash
# Never sleep
sudo pmset -a sleep 0
sudo pmset -a disablesleep 1

# Wake on network access (for SSH/ping wakeup)
sudo pmset -a womp 1

# Auto-restart after power failure
sudo pmset -a autorestart 1
```

Enable Remote Login: System Settings → General → Sharing → Remote Login → On

---

## Step 9: Verify Everything

```bash
# 1Password CLI
op account get
op vault list

# Secret injection
op inject -i ~/.config/axinova/secrets.env.tpl | head -5

# SSH to fleet
ssh agent01 'echo "M4 OK"'
ssh agent02 'echo "M2 OK"'

# VPN
ping -c 3 10.66.66.1

# GitHub
gh auth status

# Claude Code
claude --version
```

---

## Secret Migration Checklist

When migrating from current gitignored files to 1Password:

- [ ] Copy each value from `~/.config/axinova/*.env` on M4/M2 into 1Password vault
- [ ] Create `~/.config/axinova/secrets.env.tpl` with `op://` references (see Step 3e)
- [ ] Run `op inject` to regenerate `secrets.env` from vault
- [ ] Verify agent-launcher.sh still works: `scripts/fleet-status.sh`
- [ ] **CRITICAL: Rotate the Vikunja token** — it was hardcoded in 19 plist files (see below)
- [ ] After rotation, update the value in 1Password vault
- [ ] Re-run `op inject` to update `secrets.env` on all machines

### Critical: Fix Hardcoded Vikunja Token

The token `tk_c92243afb12553b93ee222f1f6c242fb0b746800` is hardcoded in all 19 plist files
and in `fleet-status.sh`. This must be fixed:

```bash
# 1. Generate a new Vikunja API token (in Vikunja UI → User Settings → API Tokens)
# 2. Store the new token in 1Password vault under "Vikunja Token"
# 3. On each fleet machine, source the new secrets.env:
source ~/.config/axinova/secrets.env
# 4. Update plists to read from env file instead of hardcoding:
#    Remove <key>VIKUNJA_TOKEN</key> from plists
#    Add to secrets.env.tpl: VIKUNJA_TOKEN=op://Axinova/Vikunja Token/password
# 5. Revoke the old token in Vikunja UI
```

For the plists: change `VIKUNJA_TOKEN` env key to be read from the secrets file
that agent-launcher.sh already sources at startup (it loads `~/.config/axinova/secrets.env`).

---

## Launchd Daemon Secret Pattern (for M4/M2 Fleet Agents)

Existing fleet agents need the same fix. Use `OP_SERVICE_ACCOUNT_TOKEN` stored in
macOS Keychain for unattended `op run` in daemons:

```bash
# On M4 and M2 (run once per machine):
# 1. Create a 1Password Service Account at my.1password.com → Integrations
# 2. Store the SA token in macOS Keychain (not in code)
security add-generic-password \
    -a "op-service-account" \
    -s "1password" \
    -w "ops_your_service_account_token_here"

# 3. In daemon wrapper scripts, retrieve the SA token:
OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -a op-service-account -s 1password -w)
export OP_SERVICE_ACCOUNT_TOKEN

# 4. Then resolve secrets:
op inject -i ~/.config/axinova/secrets.env.tpl -o ~/.config/axinova/secrets.env
```

This keeps all secrets out of plist files and version control.

---

## Quick Reference

```bash
# Refresh secrets after 1Password change
op inject -i ~/.config/axinova/secrets.env.tpl -o ~/.config/axinova/secrets.env

# Get tunnel URL
cat /tmp/claude-tunnel.log | grep https://

# Check launchd services
launchctl list | grep axinova

# Restart claude tunnel
launchctl kickstart -k gui/$(id -u)/com.axinova.claude-tunnel

# SSH to fleet machines
ssh agent01   # M4 via VPN
ssh agent02   # M2 via VPN
```

---

## Step 10: Claude Code Skills (Vikunja Fleet Management)

Custom slash commands for managing the agent fleet from Claude Code sessions.
Install by creating `~/.claude/skills/<skill-name>/SKILL.md`.

```bash
# Skills live here (one directory per skill):
ls ~/.claude/skills/
```

### Installed Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `ax-pickup-task` | `/ax-pickup-task 247` | Claim a Needs Founder task, prep workspace branch, start work |
| `ax-complete-task` | `/ax-complete-task 247` | Create PR, update Vikunja to In Review / Done |
| `ax-reroute-task` | `/ax-reroute-task 247 codex` | Send escalated task back to builders with better instructions |
| `ax-task-status` | `/ax-task-status` | Fleet overview — all kanban buckets at a glance |
| `ax-create-agent-project` | `/ax-create-agent-project` | Create new Vikunja project with full 5-bucket kanban + wave labels |
| `ax-test-mcp-project` | `/ax-test-mcp-project` | Run MCP e2e tests after changing axinova-mcp-server-go |
| `ax-test-scheduler` | `/ax-test-scheduler` | Run scheduler e2e tests after changing agent-launcher.sh |

### Typical Founder Workflow

```
# See what needs attention
/ax-task-status

# Pick up a task escalated by agents
/ax-pickup-task 247
... do the work ...
/ax-complete-task 247

# Send an over-escalated task back to agents with better spec
/ax-reroute-task 247 codex

# Create a new sprint project for agents
/ax-create-agent-project
```

### Re-installing Skills

The skill files are not in git (they live in `~/.claude/`). To replicate this setup
on a new machine, copy from the m1-workstation:

```bash
scp -r ax-workstation@10.66.66.4:~/.claude/skills/ ~/.claude/skills/
```

Or refer to the source `.codex/skills/` in this repo for the Codex CLI equivalents
(same logic, different format).

---

## Related Pages

- [[docs/runbooks/onboarding-new-macmini]] — fleet agent machine setup
- [[docs/runbooks/remote-access]] — RustDesk and VPN remote access
- [[MEMORY.md]] — VPN system details (AmneziaWG params)
- [[docs/AGENT_TEAMS.md]] — fleet architecture
