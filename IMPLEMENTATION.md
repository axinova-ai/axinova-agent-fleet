# Agent Fleet Implementation Guide

Step-by-step guide to deploy the agent fleet infrastructure.

## Prerequisites

- [x] Two Mac minis (M4 and M2 Pro)
- [ ] GitHub organization admin access (axinova-ai)
- [ ] Aliyun Singapore server access (for VPN setup)
- [ ] 1Password account with CLI access
- [ ] Physical access to Mac minis (for initial setup)

## Timeline

**Total: 7-10 days** (or 2-3 days if parallelizing and working full-time)

---

## Phase 1: Foundation (Days 1-2)

### Step 1.1: Create GitHub Repository

```bash
# On your laptop
cd /Users/weixia/axinova/axinova-agent-fleet

# Add GitHub remote (replace with actual repo URL)
git remote add origin git@github.com:axinova-ai/axinova-agent-fleet.git

# Push initial commit
git push -u origin main
```

**Verify:** Repository visible at https://github.com/axinova-ai/axinova-agent-fleet

---

### Step 1.2: Create GitHub Bot Accounts

Follow detailed guide: [bootstrap/github/create-bot-account.md](bootstrap/github/create-bot-account.md)

**Quick summary:**

1. **Create accounts:**
   - Sign up at https://github.com/signup
   - Emails: `agent1@axinova-ai.com`, `agent2@axinova-ai.com`
   - Usernames: `axinova-agent1-bot`, `axinova-agent2-bot`

2. **Add to organization:**
   - Go to https://github.com/orgs/axinova-ai/people
   - Invite both accounts as **Members**

3. **Create fine-grained PATs:**
   - Settings → Developer settings → Personal access tokens → Fine-grained tokens
   - Repository access: Only select repos (home-go, home-web, miniapp-builder-go/web, deploy)
   - Permissions: `contents:write`, `pull_requests:write`, `issues:write`, `metadata:read`
   - Expiration: 1 year

4. **Store tokens in 1Password:**
   ```bash
   # Install 1Password CLI if needed
   brew install --cask 1password-cli

   # Store tokens (interactive)
   op item create \
     --category=password \
     --title="GitHub Bot Token - Agent1" \
     --vault="Axinova" \
     password="<PASTE_TOKEN>" \
     --tags="github,agent-fleet,bot"

   op item create \
     --category=password \
     --title="GitHub Bot Token - Agent2" \
     --vault="Axinova" \
     password="<PASTE_TOKEN>" \
     --tags="github,agent-fleet,bot"
   ```

**Verify:** `op item list --tags=agent-fleet` shows both tokens

---

### Step 1.3: Bootstrap M4 Mac Mini (Agent1)

**Physical setup:**
1. Connect M4 mini to monitor, keyboard, mouse
2. Power on, complete macOS setup wizard
3. Create initial admin user (e.g., `weixia`)
4. Enable Remote Login: System Settings → Sharing → Remote Login (ON)
5. Connect to same Wi-Fi network as your laptop

**Bootstrap script:**

```bash
# From your laptop, find M4 mini IP
ping m4-mini.local  # Note the IP address

# SSH to M4 mini
ssh weixia@m4-mini.local  # Or use IP address

# Download and run bootstrap script
curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash

# Script will:
# 1. Install Homebrew
# 2. Install dependencies (Go, Node, Docker, etc.)
# 3. Create axinova-agent user
# 4. Set up SSH keys
# 5. Clone agent-fleet repo
```

**Manual steps after bootstrap:**

```bash
# Switch to axinova-agent user
sudo -i -u axinova-agent

# Configure GitHub authentication
cd ~/workspace/axinova-agent-fleet
./bootstrap/github/setup-bot-token.sh 1  # Agent1

# Verify setup
go version       # Should show 1.24+
node --version   # Should show 22+
docker --version # Should work
gh auth status   # Should show logged in as axinova-agent1-bot
```

**Verify:** Can SSH from laptop: `ssh axinova-agent@m4-mini.local`

---

### Step 1.4: Bootstrap M2 Pro Mac Mini (Agent2)

Repeat Step 1.3 for M2 Pro mini:

```bash
# From your laptop
ssh weixia@m2-mini.local

# Run bootstrap
curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash

# Switch user and configure
sudo -i -u axinova-agent
cd ~/workspace/axinova-agent-fleet
./bootstrap/github/setup-bot-token.sh 2  # Agent2
```

**Verify:** Can SSH from laptop: `ssh axinova-agent@m2-mini.local`

---

### Step 1.5: Configure SSH Config on Laptop

```bash
# Add to ~/.ssh/config on your laptop
cat >> ~/.ssh/config <<EOF

Host agent1
  HostName m4-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60

Host agent2
  HostName m2-mini.local
  User axinova-agent
  IdentityFile ~/.ssh/id_ed25519
  ForwardAgent yes
  ServerAliveInterval 60
EOF
```

**Verify:** `ssh agent1` and `ssh agent2` work

---

## Phase 2: Networking (Days 2-3)

### Step 2.1: Set Up WireGuard VPN on Aliyun Server

**On Aliyun Singapore server:**

```bash
# SSH to server
ssh root@<aliyun-sg-ip>

# Install WireGuard
apt update && apt install -y wireguard

# Generate server keys
cd /etc/wireguard
wg genkey | tee privatekey | wg pubkey > publickey
chmod 600 privatekey

# Create config
cat > wg0.conf <<EOF
[Interface]
Address = 10.100.0.1/24
ListenPort = 51820
PrivateKey = $(cat privatekey)

# Clients will be added here
EOF

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Open firewall
ufw allow 51820/udp
```

**Verify:** `wg show wg0` shows interface running

---

### Step 2.2: Configure WireGuard Clients (Mac Minis)

**On each Mac mini:**

```bash
# SSH to Mac mini
ssh agent1  # or agent2

# Run WireGuard setup
cd ~/workspace/axinova-agent-fleet/bootstrap/vpn
./wireguard-install.sh

# This generates keys and creates config template
# Copy public key (shown in output)
```

**Add clients to server:**

```bash
# On Aliyun server, edit /etc/wireguard/wg0.conf
sudo vim /etc/wireguard/wg0.conf

# Add for Agent1 (M4 mini):
[Peer]
PublicKey = <AGENT1_PUBLIC_KEY>
AllowedIPs = 10.100.0.10/32

# Add for Agent2 (M2 Pro mini):
[Peer]
PublicKey = <AGENT2_PUBLIC_KEY>
AllowedIPs = 10.100.0.11/32

# Add for your laptop (optional):
[Peer]
PublicKey = <LAPTOP_PUBLIC_KEY>
AllowedIPs = 10.100.0.20/32

# Reload WireGuard
systemctl restart wg-quick@wg0
```

**Configure clients:**

```bash
# On each Mac mini, edit /etc/wireguard/wg0.conf
sudo vim /etc/wireguard/wg0.conf

# Replace placeholders:
# - <CLIENT_PRIVATE_KEY>: from ~/.config/wireguard/privatekey
# - <CLIENT_IP>: 10.100.0.10 for Agent1, 10.100.0.11 for Agent2
# - <SERVER_PUBLIC_KEY>: from Aliyun server
# - <ALIYUN_SG_PUBLIC_IP>: Aliyun server's public IP

# Connect
sudo wg-quick up wg0

# Verify
ping 10.100.0.1        # Aliyun server
ping 10.100.0.11       # Other Mac mini
```

**Auto-connect on boot (optional):**

```bash
# On Mac mini
sudo brew services start wireguard-tools
```

**Verify:** Can ping VPN IPs from all devices

---

### Step 2.3: Thunderbolt Bridge Between Mac Minis

**Physical setup:**
1. Connect Thunderbolt cable between M4 and M2 Pro minis

**On each Mac mini:**
1. System Settings → Network
2. Thunderbolt Bridge should appear
3. Configure IPv4 → Manually:
   - M4 (Agent1): IP `169.254.100.1`, Subnet `255.255.255.0`
   - M2 Pro (Agent2): IP `169.254.100.2`, Subnet `255.255.255.0`

**Verify:**

```bash
# From M4 mini
ping 169.254.100.2

# From M2 Pro mini
ping 169.254.100.1

# Fast file transfer test
dd if=/dev/zero of=/tmp/test.img bs=1M count=1024  # 1GB
time scp /tmp/test.img axinova-agent@169.254.100.2:/tmp/
# Should complete in <10 seconds (multi-Gbps)
```

---

## Phase 3: CI Workflow Updates (Day 3)

### Step 3.1: Update GitHub Actions Workflows

For each repo (axinova-home-go, axinova-miniapp-builder-go, axinova-ai-lab-go):

**File:** `.github/workflows/go-ci.yml`

```yaml
# Only run on PR to main or push to main (not on agent/* branches)
on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]
  workflow_dispatch:
```

**File:** `.github/workflows/deploy-dev.yml`

```yaml
on:
  push:
    branches:
      - 'feature/**'
      # Exclude agent branches
      - '!agent/**'
      - '!dev'
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  workflow_dispatch:
```

**Create PR for each repo:**

```bash
# Example for axinova-home-go
cd ~/axinova/axinova-home-go
git checkout -b update-ci-triggers
# Edit .github/workflows/*.yml
git add .github/workflows/
git commit -m "Update CI: exclude agent branches

Only run GitHub Actions on PR to main or push to main.
Agent branches (agent/*, dev) run local CI instead.

This avoids consuming GitHub Actions minutes for agent work."
git push origin update-ci-triggers
gh pr create --title "Update CI triggers" --body "..."

# Merge after review
```

---

### Step 3.2: Configure Branch Protection

**On GitHub.com for each repo:**

1. Settings → Branches → Add rule
2. Branch name pattern: `main`
3. Enable:
   - Require pull request before merging
   - Require approvals: 1
   - Require status checks to pass: `build` (from go-ci.yml)
   - Include administrators
4. Save

**Verify:** Try pushing directly to main (should be blocked)

---

## Phase 4: Local CI Runners (Days 4-5)

### Step 4.1: Test Local CI Scripts

**On M4 Mac mini (Agent1):**

```bash
ssh agent1
cd ~/workspace/axinova-agent-fleet

# Clone target repos
git clone git@github.com:axinova-ai/axinova-home-go.git ~/workspace/axinova-home-go
git clone git@github.com:axinova-ai/axinova-home-web.git ~/workspace/axinova-home-web

# Test backend CI
./runners/local-ci/run_ci.sh backend ~/workspace/axinova-home-go

# Expected output:
# ==> Running Go CI for axinova-home-go
# → Tidying dependencies...
# → Formatting code...
# → Running go vet...
# → Running tests with race detector...
# → Running govulncheck...
# ✅ Go CI passed for axinova-home-go

# Test frontend CI
./runners/local-ci/run_ci.sh frontend ~/workspace/axinova-home-web

# Test full-stack
./runners/local-ci/run_ci.sh full-stack ~/workspace/axinova-home
```

**Troubleshooting:**

- **Tests fail:** Fix tests first, CI is working correctly
- **govulncheck errors:** Update dependencies with vulnerabilities
- **Docker not running:** Start Docker Desktop

---

### Step 4.2: Test Docker Build

```bash
# On M4 mini
cd ~/workspace/axinova-home-go

# Build Docker image
~/workspace/axinova-agent-fleet/runners/local-ci/run_ci.sh docker .

# Expected output:
# ==> Building Docker image for axinova-home-go
# → Building image: ghcr.io/axinova-ai/axinova-home-go:sha-abc123
# → Scanning for vulnerabilities...
# ✅ Docker build complete

# Verify image
docker images | grep axinova-home-go
```

---

## Phase 5: MCP Integration (Days 5-6)

### Step 5.1: Configure MCP Server Access

**On each Mac mini:**

```bash
ssh agent1  # or agent2

# Create MCP config directory
mkdir -p ~/.config/claude

# Copy config template
cp ~/workspace/axinova-agent-fleet/integrations/mcp/agent-mcp-config.json ~/.config/claude/config.json

# Edit config with actual tokens
vim ~/.config/claude/config.json

# Replace placeholders:
# - ptr_xxx → Portainer token (from 1Password)
# - glsa_xxx → Grafana token
# - sb_xxx → SilverBullet token
# - tk_xxx → Vikunja token
```

**Retrieve tokens from 1Password:**

```bash
# Get Portainer token
op item get "Portainer API Token" --fields password

# Get Grafana token
op item get "Grafana API Token" --fields password

# Get SilverBullet token
op item get "SilverBullet API Token" --fields password

# Get Vikunja token
op item get "Vikunja API Token" --fields password
```

---

### Step 5.2: Test MCP Integration

```bash
# On Mac mini
cd ~/workspace/axinova-mcp-server-go

# Build MCP server if not already built
make build

# Test Vikunja task creation
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"vikunja_list_projects","arguments":{}},"id":1}' | ./bin/axinova-mcp-server

# Expected: JSON response with project list

# Test task creation
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"vikunja_create_task","arguments":{"project_id":1,"title":"Test from agent"}},"id":2}' | ./bin/axinova-mcp-server

# Verify on Vikunja web UI: https://vikunja.axinova-internal.xyz
```

---

## Phase 6: Agent Runtime Installation (Days 6-7)

### Step 6.1: Install Anthropic SDK (Agent1)

**On M4 Mac mini:**

```bash
ssh agent1

# Install Anthropic SDK
go install github.com/anthropics/anthropic-sdk-go/v2@latest

# Set API key (from 1Password)
export ANTHROPIC_API_KEY=$(op item get "Anthropic API Key" --fields password)

# Add to ~/.zshrc for persistence
echo 'export ANTHROPIC_API_KEY=$(op item get "Anthropic API Key" --fields password)' >> ~/.zshrc

# Test basic API call
cat > ~/test_claude.go <<'EOF'
package main

import (
    "context"
    "fmt"
    "os"

    "github.com/anthropics/anthropic-sdk-go/v2"
)

func main() {
    client := anthropic.NewClient(anthropic.WithAPIKey(os.Getenv("ANTHROPIC_API_KEY")))

    resp, err := client.Messages.New(context.Background(), &anthropic.MessageRequest{
        Model: "claude-sonnet-4-5-20250929",
        Messages: []anthropic.Message{
            {Role: "user", Content: "Hello! Can you list files in current directory?"},
        },
        MaxTokens: 1024,
    })

    if err != nil {
        panic(err)
    }

    fmt.Println(resp.Content[0].Text)
}
EOF

go run ~/test_claude.go
# Should return a response from Claude
```

---

### Step 6.2: Install OpenClaw (Agent2) - Optional

**On M2 Pro Mac mini:**

```bash
ssh agent2

# Install OpenClaw (placeholder - adjust based on actual installation)
# This is speculative; OpenClaw may not be released yet
# Alternative: Use Anthropic SDK for code tasks, manual CLI for general tasks

# For now, install same Anthropic SDK as Agent1
go install github.com/anthropics/anthropic-sdk-go/v2@latest
export ANTHROPIC_API_KEY=$(op item get "Anthropic API Key" --fields password)
```

---

## Phase 7: End-to-End Testing (Day 7)

### Step 7.1: Test Full Workflow

**Scenario:** Agent1 makes a small change, runs local CI, creates PR

```bash
# On M4 mini (Agent1)
ssh agent1

cd ~/workspace/axinova-home-go

# Create feature branch
git checkout -b agent1/test-ci-workflow

# Make a trivial change
echo "// Test comment" >> internal/api/health.go
git add internal/api/health.go
git commit -m "Test: agent CI workflow

Testing local CI → GitHub PR flow.

Co-Authored-By: Agent Fleet <agent@axinova-ai.com>"

# Run local CI
~/workspace/axinova-agent-fleet/runners/local-ci/run_ci.sh backend .

# If CI passes, push to GitHub
git push origin agent1/test-ci-workflow

# Create PR
gh pr create \
  --title "Test: Agent CI workflow" \
  --body "Testing local CI before GitHub push.

## Checklist
- [x] Local CI passed
- [x] Branch pushed
- [ ] Human review

This PR should NOT trigger GitHub Actions (agent/* branch excluded)." \
  --draft

# Verify on GitHub: No workflow runs triggered
```

**On your laptop:**

```bash
# Review PR
gh pr view <PR_NUMBER> --web

# Verify no CI runs triggered
gh run list --limit 5

# Approve and merge
gh pr review <PR_NUMBER> --approve
gh pr merge <PR_NUMBER>

# Now CI should run (merged to main)
gh run watch
```

**Verify:** GitHub Actions only ran after merge to main, not on agent branch push

---

### Step 7.2: Test Full-Stack Deployment

```bash
# On M4 mini (Agent1)
ssh agent1

# Run full-stack deployment to dev
~/workspace/axinova-agent-fleet/runners/orchestration/full-stack-deploy.sh axinova-home dev

# Expected:
# ==> Full-stack deployment: axinova-home (dev)
# → Running backend CI...
# ✅ Go CI passed
# → Running frontend CI...
# ✅ Vue CI passed
# → Building backend Docker image...
# ✅ Docker build complete
# → Updating deployment values...
# ✅ Values updated
# → Pushing to dev branch...
# ✅ Full-stack deployment complete

# Verify deployment
curl https://axinova-home.axinova-dev.xyz/api/health
# Should return: {"status":"ok"}
```

---

## Phase 8: Documentation and Handoff (Day 8)

### Step 8.1: Create SilverBullet Runbooks

**Agent2 task:** Document the fleet setup in wiki

```bash
# On M2 Pro mini (Agent2)
ssh agent2

# Create wiki pages (via MCP)
# Example: Bootstrap runbook, CI usage, troubleshooting

# For now, manually create in SilverBullet web UI:
# - bootstrap/mac-mini-setup
# - ci/local-ci-usage
# - troubleshooting/common-issues
```

---

### Step 8.2: Create Vikunja Project

**Create "Agent Fleet" project in Vikunja:**

1. Go to https://vikunja.axinova-internal.xyz
2. Create new project: "Agent Fleet Operations"
3. Create initial tasks:
   - [ ] Set up Agent1 runtime with task scheduling
   - [ ] Set up Agent2 runtime with research focus
   - [ ] Create daily standup automation
   - [ ] Implement AI learning experiment (character-level transformer)

---

## Verification Checklist

### Infrastructure

- [ ] Both Mac minis accessible via SSH from laptop
- [ ] VPN connected (can ping 10.100.0.1 from minis)
- [ ] Thunderbolt bridge working (fast file transfer)
- [ ] Docker Desktop running on both minis
- [ ] All dependencies installed (Go, Node, gh, etc.)

### GitHub Integration

- [ ] Bot accounts created and added to org
- [ ] Fine-grained PATs stored in 1Password
- [ ] Git configured with bot identities
- [ ] Can create PRs from agent accounts
- [ ] Branch protection on main (requires approval)

### CI/CD

- [ ] Local CI scripts work (backend, frontend, docker)
- [ ] GitHub Actions only trigger on main (not agent/*)
- [ ] Full-stack deployment script works
- [ ] Health checks pass after deployment

### MCP Integration

- [ ] MCP server accessible from agents
- [ ] Can create Vikunja tasks via MCP
- [ ] Can update SilverBullet wiki via MCP
- [ ] Can query Portainer, Grafana, Prometheus

### Security

- [ ] SSH key-based auth only (password auth disabled)
- [ ] Secrets stored in 1Password, not git
- [ ] WireGuard VPN encrypted
- [ ] Firewall configured on minis
- [ ] SOPS encryption for deployment secrets

---

## Next Steps

After completing this implementation:

1. **Create task backlog** in Vikunja for Agent1 and Agent2
2. **Set up agent runtimes** to continuously poll Vikunja for tasks
3. **Configure alerts** (Prometheus/Grafana) for agent failures
4. **Implement AI learning project** (character-level transformer on Agent2)
5. **Monitor GitHub Actions minutes** (should drop to near-zero for dev work)

---

## Troubleshooting

### SSH Connection Issues

**Problem:** Cannot SSH to Mac mini

**Solutions:**
1. Check if Mac mini is powered on and connected to network
2. Verify VPN: `ping 10.100.0.10` (or .11 for Agent2)
3. Try LAN: `ssh axinova-agent@192.168.1.x` (find IP in router)
4. Check firewall: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`

### VPN Connection Fails

**Problem:** `wg-quick up wg0` fails

**Solutions:**
1. Check server is running: `ssh root@<aliyun-ip> wg show wg0`
2. Verify config: `sudo cat /etc/wireguard/wg0.conf` (correct IPs, keys)
3. Check firewall: `sudo ufw status` (port 51820 open)
4. Logs: `sudo journalctl -u wg-quick@wg0 -n 50`

### Local CI Fails

**Problem:** `run_ci.sh backend` returns errors

**Solutions:**
1. Check if tests pass locally: `cd ~/workspace/axinova-home-go && go test ./...`
2. Fix test failures (CI is working correctly)
3. Update dependencies: `go get -u ./... && go mod tidy`
4. Check govulncheck: `govulncheck ./...` (patch vulnerabilities)

### GitHub Actions Still Triggering

**Problem:** Push to `agent/*` branch triggers CI

**Solutions:**
1. Verify workflow file: `cat .github/workflows/go-ci.yml` (should only have `branches: [ main ]`)
2. Clear workflow cache: Settings → Actions → Clear cache
3. Check branch protection: Ensure agent/* not in required checks

---

## Support

For issues not covered here:
1. Check docs/runbooks/
2. Search SilverBullet wiki
3. Create GitHub issue in axinova-agent-fleet repo
4. Escalate to human for critical issues
