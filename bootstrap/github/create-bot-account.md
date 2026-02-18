# GitHub Setup for Agent Fleet

This guide covers GitHub authentication for the agent fleet using **your existing GitHub account** with per-machine SSH keys and git identities.

## Overview

Instead of creating separate bot accounts, each Mac mini uses:
- **Your GitHub account** (`harryxiaxia`) for authentication
- **Per-machine SSH keys** for push access
- **Per-machine git identity** for commit attribution
- **Per-machine branch prefix** for traceability

## Step-by-Step Setup

### 1. Generate SSH Key (on each Mac mini)

**On M4 Mac Mini:**
```bash
ssh-keygen -t ed25519 -C "axinova-m4-agent" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

**On M2 Pro Mac Mini:**
```bash
ssh-keygen -t ed25519 -C "axinova-m2pro-agent" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

### 2. Add SSH Keys to Your GitHub Account

1. Go to https://github.com/settings/keys
2. Click "New SSH key"
3. Title: `axinova-m4-agent` (or `axinova-m2pro-agent`)
4. Paste the public key from step 1
5. Click "Add SSH key"

### 3. Configure Git Identity (on each Mac mini)

**On M4 Mac Mini:**
```bash
git config --global user.name "Axinova M4 Agent"
git config --global user.email "m4@axinova.local"
```

**On M2 Pro Mac Mini:**
```bash
git config --global user.name "Axinova M2Pro Agent"
git config --global user.email "m2pro@axinova.local"
```

### 4. Authenticate GitHub CLI

On each machine, create a fine-grained PAT from your account:

1. Go to https://github.com/settings/personal-access-tokens/new
2. Token name: `Agent Fleet - M4` (or `M2Pro`)
3. Expiration: **1 year** (set calendar reminder to rotate)
4. Resource owner: **axinova-ai**
5. Repository access: **All repositories** (or select specific ones)
6. Permissions:
   - Contents: **Read and write**
   - Pull requests: **Read and write**
   - Issues: **Read and write**
   - Metadata: **Read-only**
7. Generate and copy token

Then on the Mac mini:
```bash
gh auth login --with-token <<< "<PASTE_TOKEN>"
gh auth status   # Should show: Logged in to github.com account harryxiaxia
```

## Branch Strategy

Each agent creates branches with a standard prefix:
```
agent/<role>/task-<vikunja-id>
```

Examples:
- `agent/backend-sde/task-42`
- `agent/frontend-sde/task-55`
- `agent/devops/task-67`

The machine is identified in the PR body (via `$(hostname -s)`) and commit author.

## Result

| Aspect | Value |
|--------|-------|
| PR author | `harryxiaxia` (your account) |
| Commit author | `Axinova M4 Agent <m4@axinova.local>` |
| Branch | `agent/backend-sde/task-42` |
| Machine ID | In PR body and commit metadata |

## Token Scopes Explained

| Scope | Purpose |
|-------|---------|
| `contents:write` | Push commits, create branches |
| `pull_requests:write` | Create PRs |
| `issues:write` | Create issues, add labels |
| `metadata:read` | Required for API access |

## Security Notes

1. **SSH keys** are per-machine — revoke individually if compromised
2. **PATs** can be scoped per-machine — rotate annually
3. **Commit emails** (`m4@axinova.local`) don't link to any GitHub account, providing clear visual distinction
4. **Audit:** GitHub activity log shows all actions under `harryxiaxia` — filter by commit author to distinguish machines

## Verification

```bash
# Test SSH access
ssh -T git@github.com   # Should say: Hi harryxiaxia!

# Test gh CLI
gh auth status           # Should show: Logged in to github.com account harryxiaxia

# Test push (dry run)
git clone git@github.com:axinova-ai/axinova-home-go.git /tmp/test-push
cd /tmp/test-push
git checkout -b agent/test-setup
git commit --allow-empty -m "test: verify agent push access"
git push -u origin agent/test-setup
gh pr create --title "Test: agent setup" --body "Testing agent push access. Safe to close."
# Clean up: close PR and delete branch
```
