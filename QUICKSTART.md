# Quick Start Guide

Fast track to getting the agent fleet operational.

## Prerequisites (5 minutes)

1. **GitHub bot accounts created** ([guide](bootstrap/github/create-bot-account.md))
2. **Bot tokens in 1Password** (names: "GitHub Bot Token - Agent1/2")
3. **Mac minis on network** (can ping m4-mini.local, m2-mini.local)

## Bootstrap Mac Mini (15 minutes per mini)

```bash
# SSH to Mac mini
ssh your-user@m4-mini.local  # or m2-mini.local

# Run bootstrap (one command)
curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash

# Switch to agent user
sudo -i -u axinova-agent

# Configure GitHub
cd ~/workspace/axinova-agent-fleet
./bootstrap/github/setup-bot-token.sh 1  # Use 2 for Agent2

# Verify
go version && node --version && docker --version && gh auth status
```

## Test Local CI (5 minutes)

```bash
# Clone a test repo
git clone git@github.com:axinova-ai/axinova-home-go.git ~/workspace/axinova-home-go

# Run CI
cd ~/workspace/axinova-agent-fleet
./runners/local-ci/run_ci.sh backend ~/workspace/axinova-home-go

# Expected: ✅ Go CI passed
```

## Update GitHub Workflows (10 minutes per repo)

```bash
# On your laptop
cd ~/axinova/axinova-home-go

# Edit workflow
vim .github/workflows/go-ci.yml

# Change to:
on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]
  workflow_dispatch:

# Commit and push
git checkout -b update-ci-triggers
git add .github/workflows/
git commit -m "CI: exclude agent branches"
git push origin update-ci-triggers
gh pr create --title "Update CI triggers" --body "Exclude agent/* from GitHub Actions"

# Merge after review
```

## Daily Usage

### Run Local CI Before Push

```bash
# On Mac mini (Agent1)
ssh agent1

cd ~/workspace/axinova-home-go

# Make changes
git checkout -b agent1/my-feature
# ... edit code ...

# Run CI BEFORE pushing
~/workspace/axinova-agent-fleet/runners/local-ci/run_ci.sh backend .

# If passed, push and create PR
git push origin agent1/my-feature
gh pr create --title "My feature" --body "..."
```

### Deploy to Dev

```bash
# On Mac mini (Agent1)
~/workspace/axinova-agent-fleet/runners/orchestration/full-stack-deploy.sh axinova-home dev
```

### Check Fleet Status

```bash
# From your laptop
ssh agent1 'cd ~/workspace/axinova-agent-fleet && ./scripts/fleet-status.sh'
```

## Common Commands

```bash
# SSH to agents
ssh agent1  # M4 mini
ssh agent2  # M2 Pro mini

# Or use convenience scripts
cd ~/axinova/axinova-agent-fleet
./scripts/ssh-to-agent1.sh
./scripts/ssh-to-agent2.sh

# Check status
./scripts/fleet-status.sh

# Run local CI
./runners/local-ci/run_ci.sh backend <repo-path>
./runners/local-ci/run_ci.sh frontend <repo-path>
./runners/local-ci/run_ci.sh full-stack <base-repo-path>

# Deploy
./runners/orchestration/full-stack-deploy.sh <service> <env>
```

## Troubleshooting

**Cannot SSH to Mac mini:**
```bash
# Try VPN IP
ssh axinova-agent@10.100.0.10  # Agent1
ssh axinova-agent@10.100.0.11  # Agent2

# Or LAN
ping m4-mini.local  # Find IP
ssh axinova-agent@<IP>
```

**Local CI fails:**
```bash
# Check what failed
cd ~/workspace/axinova-home-go
go test ./...           # If tests fail
go vet ./...            # If vet fails
govulncheck ./...       # If vulncheck fails

# Fix issues, then re-run CI
```

**GitHub Actions still triggering:**
```bash
# Verify workflow file
cat .github/workflows/go-ci.yml
# Should have: branches: [ main ]

# Check recent runs
gh run list --limit 5

# Cancel unwanted runs
gh run cancel <RUN_ID>
```

## Next Steps

1. **Set up VPN:** [bootstrap/vpn/wireguard-install.sh](bootstrap/vpn/wireguard-install.sh)
2. **Configure MCP:** [integrations/mcp/agent-mcp-config.json](integrations/mcp/agent-mcp-config.json)
3. **Read full guide:** [IMPLEMENTATION.md](IMPLEMENTATION.md)
4. **Review security:** [docs/threat-model.md](docs/threat-model.md)

## Help

- **Implementation guide:** [IMPLEMENTATION.md](IMPLEMENTATION.md)
- **Summary:** [SUMMARY.md](SUMMARY.md)
- **Runbooks:** [docs/runbooks/](docs/runbooks/)
- **Issues:** https://github.com/axinova-ai/axinova-agent-fleet/issues
