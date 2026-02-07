# GitHub Bot Account Creation

This guide walks through creating GitHub bot accounts for the agent fleet.

## Accounts Needed

1. **axinova-agent1-bot** (M4 Mac mini - Delivery)
2. **axinova-agent2-bot** (M2 Pro Mac mini - Learning)

## Step-by-Step Setup

### 1. Create GitHub Account

For each bot account:

1. Sign up at https://github.com/signup
2. Email: Use `agent1@axinova-ai.com` and `agent2@axinova-ai.com`
3. Username: `axinova-agent1-bot` and `axinova-agent2-bot`
4. Verify email

### 2. Add to Organization

1. Go to https://github.com/orgs/axinova-ai/people
2. Click "Invite member"
3. Enter bot username
4. Role: **Member** (not owner)
5. Send invitation, accept from bot account

### 3. Create Fine-Grained Personal Access Token

**For each bot account:**

1. Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Click "Generate new token"
3. Token name: `Agent Fleet - [Agent1/Agent2]`
4. Expiration: **1 year** (set calendar reminder to rotate)
5. Resource owner: **axinova-ai**
6. Repository access: **Only select repositories**
   - Agent1: axinova-home-go, axinova-home-web, axinova-miniapp-builder-go, axinova-miniapp-builder-web, axinova-deploy
   - Agent2: axinova-ai-lab-go, axinova-deploy
7. Permissions:
   - **Repository permissions:**
     - Contents: **Read and write** (push code, create branches)
     - Pull requests: **Read and write** (create, update PRs)
     - Issues: **Read and write** (create, comment on issues)
     - Metadata: **Read-only** (required)
     - Workflows: **Read and write** (optional, for workflow dispatch)
   - **Organization permissions:**
     - Members: **Read-only** (optional, for @mentions)
8. Click "Generate token"
9. **Copy token immediately** (won't be shown again)

### 4. Store Token Securely

**Using 1Password CLI:**

```bash
# Install 1Password CLI if needed
brew install --cask 1password-cli

# Save token
op item create \
  --category=password \
  --title="GitHub Bot Token - Agent1" \
  --vault="Axinova" \
  password="<PASTE_TOKEN_HERE>" \
  --tags="github,agent-fleet,bot"

# Retrieve token later
op item get "GitHub Bot Token - Agent1" --fields password
```

### 5. Configure Git on Mac Mini

**On each Mac mini:**

```bash
# Configure git identity
git config --global user.name "Axinova Agent 1 Bot"
git config --global user.email "agent1@axinova-ai.com"

# Store token in git credential helper
git config --global credential.helper osxkeychain

# Test authentication (will prompt for token)
gh auth login --with-token < <(op item get "GitHub Bot Token - Agent1" --fields password)

# Verify
gh auth status
```

## Token Scopes Explained

| Scope | Purpose | Why Needed |
|-------|---------|------------|
| `contents:write` | Push commits, create branches | Agent needs to push code changes |
| `pull_requests:write` | Create PRs, request reviews | Agent creates PRs for deployment |
| `issues:write` | Create issues, add labels | Agent creates tasks from CI failures |
| `metadata:read` | Repository metadata | Required for API access |
| `workflows:write` | Trigger workflow dispatch | Optional, for manual CI triggers |

## Security Best Practices

1. **Minimal scope:** Only grant permissions needed for agent's role
2. **Repository-specific:** Never use "All repositories" access
3. **Annual rotation:** Set calendar reminder to rotate tokens yearly
4. **Audit logs:** Regularly review bot activity in GitHub audit log
5. **Revoke on compromise:** If token leaked, revoke immediately and regenerate

## Verification

```bash
# Test token (should list repos bot can access)
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user/repos

# Test PR creation (dry-run)
gh pr create --repo axinova-ai/axinova-home-go --dry-run \
  --title "Test PR" --body "Testing bot access"
```

## Troubleshooting

**Error: "Resource not accessible by integration"**
→ Token scope insufficient, regenerate with correct permissions

**Error: "Bad credentials"**
→ Token expired or revoked, create new token

**Error: "Not Found"**
→ Bot account not added to organization or repo not in allowed list
