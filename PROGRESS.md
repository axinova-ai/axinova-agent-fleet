# Agent Fleet Implementation Progress

Last Updated: 2026-02-08

## Project Overview

**Goal:** Build a multi-agent team infrastructure running on two Mac minis to avoid GitHub Actions costs and enable autonomous software development.

**Timeline:** 8 phases over 7-10 days (initial setup), then continuous operation

**Current Status:** ✅ Phase 1-2 Complete (Foundation + Planning), 🚧 Phase 3 In Progress (Deployment)

---

## Phase 1: Foundation & Planning ✅ COMPLETE

**Duration:** Days 1-2 (Feb 7-8, 2026)

### Completed Tasks

- [x] Create `axinova-agent-fleet` repository
- [x] Push to GitHub: https://github.com/axinova-ai/axinova-agent-fleet
- [x] Design two-team architecture (Agent Team 1 + Team 2)
- [x] Define 10 specialized agent roles:
  - Backend Engineer, Frontend Engineer, DevOps Engineer
  - Product Manager, Sales & Marketing
  - AI Researcher, Researcher & Data Analyst
  - Customer Support, QA & Testing, Technical Writer
- [x] Write bootstrap scripts (Mac mini setup)
- [x] Create VPN configuration templates (WireGuard)
- [x] Document GitHub bot account setup process
- [x] Create local CI scripts (Go, Vue, Docker)
- [x] Write deployment orchestration scripts
- [x] Document threat model and security mitigations
- [x] Create comprehensive runbooks (SSH, agent roles, rollback)
- [x] Write LLM learning journey plan (character-level transformer + Llama 3 fine-tuning)

### Deliverables

| Deliverable | Status | Location |
|-------------|--------|----------|
| Repository structure | ✅ Complete | `/` |
| Bootstrap scripts | ✅ Complete | `bootstrap/mac/` |
| VPN setup scripts | ✅ Complete | `bootstrap/vpn/` |
| GitHub bot setup guide | ✅ Complete | `bootstrap/github/` |
| Local CI runners | ✅ Complete | `runners/local-ci/` |
| Deployment orchestration | ✅ Complete | `runners/orchestration/` |
| MCP integration examples | ✅ Complete | `integrations/mcp/` |
| Agent team documentation | ✅ Complete | `docs/AGENT_TEAMS.md` |
| LLM learning journey | ✅ Complete | `docs/LLM_LEARNING_JOURNEY.md` |
| Threat model | ✅ Complete | `docs/threat-model.md` |
| Runbooks | ✅ Complete | `docs/runbooks/` |
| Quick start guide | ✅ Complete | `QUICKSTART.md` |
| Implementation guide | ✅ Complete | `IMPLEMENTATION.md` |
| Summary document | ✅ Complete | `SUMMARY.md` |

**Total Files Created:** 31 files, ~3,500 lines of code/documentation

---

## Phase 2: GitHub Bot Accounts 🚧 IN PROGRESS

**Duration:** 1-2 hours

### Tasks

- [ ] Create GitHub account: `axinova-agent1-bot` (M4 Mac mini)
  - [ ] Sign up with email: `agent1@axinova-ai.com`
  - [ ] Add to axinova-ai organization as Member
  - [ ] Generate fine-grained PAT (1 year expiration)
    - Scopes: `contents:write`, `pull_requests:write`, `issues:write`, `metadata:read`
    - Repos: home-go, home-web, miniapp-builder-go/web, deploy
  - [ ] Store token in 1Password vault

- [ ] Create GitHub account: `axinova-agent2-bot` (M2 Pro Mac mini)
  - [ ] Sign up with email: `agent2@axinova-ai.com`
  - [ ] Add to axinova-ai organization as Member
  - [ ] Generate fine-grained PAT (1 year expiration)
    - Scopes: `contents:write`, `pull_requests:write`, `issues:write`, `metadata:read`
    - Repos: ai-lab-go, deploy
  - [ ] Store token in 1Password vault

### Next Steps

Follow guide: `bootstrap/github/create-bot-account.md`

---

## Phase 3: Mac Mini Bootstrap 📅 PENDING

**Duration:** ~30 minutes per mini

### Agent Team 1 (M4 Mac Mini) - Production Team

**Tasks:**
- [ ] Physical setup (monitor, keyboard, power on)
- [ ] Initial macOS user creation
- [ ] Enable Remote Login (System Settings → Sharing)
- [ ] SSH from laptop: `ssh initial-user@m4-mini.local`
- [ ] Run bootstrap script:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash
  ```
- [ ] Switch to `axinova-agent` user
- [ ] Configure GitHub authentication: `./bootstrap/github/setup-bot-token.sh 1`
- [ ] Verify setup:
  - [ ] `go version` → 1.24+
  - [ ] `node --version` → 22+
  - [ ] `docker --version` → Working
  - [ ] `gh auth status` → Logged in as `axinova-agent1-bot`
- [ ] Test SSH from laptop: `ssh agent1`

### Agent Team 2 (M2 Pro Mac Mini) - Research & Learning Team

**Tasks:**
- [ ] Physical setup (monitor, keyboard, power on)
- [ ] Initial macOS user creation
- [ ] Enable Remote Login
- [ ] SSH from laptop: `ssh initial-user@m2-mini.local`
- [ ] Run bootstrap script
- [ ] Switch to `axinova-agent` user
- [ ] Configure GitHub authentication: `./bootstrap/github/setup-bot-token.sh 2`
- [ ] Install Python ML tools:
  ```bash
  brew install python@3.12
  pip install torch torchvision torchaudio transformers peft datasets
  ```
- [ ] Verify setup
- [ ] Test SSH from laptop: `ssh agent2`

---

## Phase 4: Networking (VPN + Thunderbolt) 📅 PENDING

**Duration:** 1-2 hours

### WireGuard VPN to Aliyun Singapore

**Tasks:**
- [ ] **On Aliyun SG server:**
  - [ ] Install WireGuard: `apt install wireguard`
  - [ ] Generate server keys
  - [ ] Create `/etc/wireguard/wg0.conf`
  - [ ] Add firewall rule: `ufw allow 51820/udp`
  - [ ] Start WireGuard: `systemctl enable wg-quick@wg0 && systemctl start wg-quick@wg0`

- [ ] **On M4 Mac mini (Agent1):**
  - [ ] Run `./bootstrap/vpn/wireguard-install.sh`
  - [ ] Copy public key to Aliyun server
  - [ ] Edit `/etc/wireguard/wg0.conf` (add server details)
  - [ ] Connect: `sudo wg-quick up wg0`
  - [ ] Verify: `ping 10.100.0.1` (Aliyun server)

- [ ] **On M2 Pro Mac mini (Agent2):**
  - [ ] Run `./bootstrap/vpn/wireguard-install.sh`
  - [ ] Copy public key to Aliyun server
  - [ ] Edit `/etc/wireguard/wg0.conf`
  - [ ] Connect: `sudo wg-quick up wg0`
  - [ ] Verify: `ping 10.100.0.1` and `ping 10.100.0.10` (Agent1)

- [ ] **Optional: Auto-connect on boot**
  - [ ] `sudo brew services start wireguard-tools` (both minis)

### Thunderbolt Bridge (High-Speed Link)

**Tasks:**
- [ ] Connect Thunderbolt cable between M4 and M2 Pro
- [ ] **On M4:** System Settings → Network → Thunderbolt Bridge
  - [ ] Configure IPv4: Manually, IP: `169.254.100.1`, Subnet: `255.255.255.0`
- [ ] **On M2 Pro:** System Settings → Network → Thunderbolt Bridge
  - [ ] Configure IPv4: Manually, IP: `169.254.100.2`, Subnet: `255.255.255.0`
- [ ] Verify: `ping 169.254.100.2` (from M4) and `ping 169.254.100.1` (from M2 Pro)
- [ ] Test file transfer speed (should be multi-Gbps)

---

## Phase 5: GitHub Workflow Updates 📅 PENDING

**Duration:** ~10 minutes per repository

### Repositories to Update

- [ ] axinova-home-go
- [ ] axinova-home-web
- [ ] axinova-miniapp-builder-go
- [ ] axinova-miniapp-builder-web
- [ ] axinova-ai-lab-go

### Tasks Per Repo

- [ ] Edit `.github/workflows/go-ci.yml` (or `ci.yml`)
  - Change trigger to:
    ```yaml
    on:
      pull_request:
        branches: [ main ]
      push:
        branches: [ main ]
      workflow_dispatch:
    ```
- [ ] Edit `.github/workflows/deploy-dev.yml` (if exists)
  - Exclude agent branches:
    ```yaml
    on:
      push:
        branches:
          - 'feature/**'
          - '!agent/**'
          - '!dev'
    ```
- [ ] Create PR with changes
- [ ] Merge after review

### Branch Protection

- [ ] Configure for each repo: Settings → Branches → Add rule
  - Branch: `main`
  - ✅ Require pull request before merging
  - ✅ Require approvals: 1
  - ✅ Require status checks: `build`
  - ✅ Include administrators

---

## Phase 6: Local CI Testing 📅 PENDING

**Duration:** 1-2 hours

### Tasks

- [ ] Clone test repositories to M4 Mac mini
  ```bash
  ssh agent1
  git clone git@github.com:axinova-ai/axinova-home-go.git ~/workspace/axinova-home-go
  git clone git@github.com:axinova-ai/axinova-home-web.git ~/workspace/axinova-home-web
  ```

- [ ] Test backend CI
  ```bash
  cd ~/workspace/axinova-agent-fleet
  ./runners/local-ci/run_ci.sh backend ~/workspace/axinova-home-go
  ```
  - [ ] Verify tests pass
  - [ ] Check coverage report
  - [ ] Confirm govulncheck runs

- [ ] Test frontend CI
  ```bash
  ./runners/local-ci/run_ci.sh frontend ~/workspace/axinova-home-web
  ```
  - [ ] Verify type check passes
  - [ ] Check build output size
  - [ ] Confirm linter runs

- [ ] Test full-stack CI
  ```bash
  ./runners/local-ci/run_ci.sh full-stack ~/workspace/axinova-home
  ```
  - [ ] Both backend and frontend pass

- [ ] Test Docker build
  ```bash
  ./runners/local-ci/run_ci.sh docker ~/workspace/axinova-home-go
  ```
  - [ ] Image builds successfully
  - [ ] Note image size

---

## Phase 7: MCP Integration 📅 PENDING

**Duration:** 1-2 hours

### Tasks

- [ ] Build axinova-mcp-server (if not already built)
  ```bash
  cd ~/axinova/axinova-mcp-server-go
  make build
  ```

- [ ] Copy MCP config to agent user
  ```bash
  ssh agent1
  mkdir -p ~/.config/claude
  cp ~/workspace/axinova-agent-fleet/integrations/mcp/agent-mcp-config.json ~/.config/claude/config.json
  ```

- [ ] Retrieve secrets from 1Password
  ```bash
  # Portainer token
  op item get "Portainer API Token" --fields password

  # Grafana token
  op item get "Grafana API Token" --fields password

  # SilverBullet token
  op item get "SilverBullet API Token" --fields password

  # Vikunja token
  op item get "Vikunja API Token" --fields password
  ```

- [ ] Edit `~/.config/claude/config.json` with actual tokens

- [ ] Test MCP tools
  ```bash
  # Test Vikunja list projects
  echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"vikunja_list_projects","arguments":{}},"id":1}' | ~/axinova/axinova-mcp-server-go/bin/axinova-mcp-server
  ```
  - [ ] Verify JSON response with project list

- [ ] Repeat for Agent2 (M2 Pro mini)

---

## Phase 8: Agent Runtime Installation 📅 PENDING

**Duration:** 2-3 hours

### Agent Team 1 (M4 Mac Mini) - Production Runtime

**Tasks:**
- [ ] Install Anthropic SDK
  ```bash
  ssh agent1
  go install github.com/anthropics/anthropic-sdk-go/v2@latest
  ```

- [ ] Configure Anthropic API key
  ```bash
  export ANTHROPIC_API_KEY=$(op item get "Anthropic API Key" --fields password)
  echo 'export ANTHROPIC_API_KEY=$(op item get "Anthropic API Key" --fields password)' >> ~/.zshrc
  ```

- [ ] Create agent runtime scripts (TODO: define exact implementation)
  - [ ] Task poller (query Vikunja every minute)
  - [ ] Agent executor (call Claude API with task context)
  - [ ] Error handler (retry, escalate)
  - [ ] Status updater (update Vikunja task)

- [ ] Test basic agent workflow
  - [ ] Create test task in Vikunja
  - [ ] Agent picks up task
  - [ ] Agent executes (e.g., create GitHub issue)
  - [ ] Agent updates task status

### Agent Team 2 (M2 Pro Mac Mini) - Research Runtime

**Tasks:**
- [ ] Install same Anthropic SDK
- [ ] Configure API key
- [ ] Install ML tools
  ```bash
  pip install torch transformers peft datasets
  ```

- [ ] Create research agent runtime
  - [ ] Experiment tracker (log to wiki)
  - [ ] Model training wrapper
  - [ ] Evaluation script runner

- [ ] Test LLM experiment workflow
  - [ ] Create task in Vikunja: "Train character-level transformer"
  - [ ] Agent picks up task
  - [ ] Agent runs training script
  - [ ] Agent logs results to SilverBullet wiki

---

## Phase 9: End-to-End Workflow Test 📅 PENDING

**Duration:** 2-3 hours

### Scenario: Backend Engineer Creates Feature

**Steps:**
- [ ] Create Vikunja task: "Add /v1/health endpoint"
  - Label: `backend`
  - Priority: 4
  - Description: "Add a health check endpoint that returns JSON with status and version"

- [ ] Backend Engineer agent picks up task
  - [ ] Clone repo (if not already)
  - [ ] Create branch: `agent1/health-endpoint`
  - [ ] Implement endpoint in `internal/api/health.go`
  - [ ] Write tests
  - [ ] Run local CI
  - [ ] Commit and push
  - [ ] Create PR on GitHub

- [ ] Human reviews PR
  - [ ] Check code quality
  - [ ] Verify tests pass
  - [ ] Approve PR

- [ ] Merge to main
  - [ ] GitHub Actions run (should be first time for agent work)
  - [ ] Verify CI passes

- [ ] DevOps agent deploys to dev
  - [ ] Run `full-stack-deploy.sh axinova-home dev`
  - [ ] Health check passes

- [ ] Verify end-to-end
  - [ ] `curl https://axinova-home.axinova-dev.xyz/v1/health` returns 200

### Success Criteria

- [ ] Vikunja task marked as completed
- [ ] GitHub PR created by `axinova-agent1-bot`
- [ ] PR merged with approval
- [ ] GitHub Actions only ran once (on merge to main, not on agent branch push)
- [ ] Deployment successful
- [ ] Health check returns correct response
- [ ] SilverBullet wiki has agent activity log

---

## Phase 10: LLM Learning Journey (Ongoing) 📅 PENDING

**Duration:** 3-6 months

### Phase 1: Character-Level Transformer (Weeks 1-4)

- [ ] **Week 1: Data Collection**
  - [ ] Collect corpus from Axinova repos (Markdown, code comments)
  - [ ] Clean and deduplicate
  - [ ] Save to `corpus.txt` (~500KB-1MB)

- [ ] **Week 2: Tokenizer + Model**
  - [ ] Implement character-level tokenizer
  - [ ] Build 2-layer transformer architecture
  - [ ] Test forward pass

- [ ] **Week 3: Training**
  - [ ] Set up training loop
  - [ ] Train for 10 epochs on M2 Pro GPU
  - [ ] Monitor loss curves
  - [ ] Save checkpoints

- [ ] **Week 4: Evaluation**
  - [ ] Compute perplexity on validation set
  - [ ] Generate text samples
  - [ ] Document findings in wiki

### Phase 2: Llama 3 Fine-Tuning (Weeks 5-8)

- [ ] **Week 5: Setup + Dataset**
  - [ ] Download Llama 3 8B via Ollama
  - [ ] Extract code examples from repos
  - [ ] Create instruction-following dataset (100-500 examples)

- [ ] **Week 6: LoRA Fine-Tuning**
  - [ ] Configure LoRA (r=8, target attention layers)
  - [ ] Train for 3 epochs
  - [ ] Save LoRA weights

- [ ] **Week 7: Evaluation**
  - [ ] Compare baseline vs. fine-tuned vs. tiny model
  - [ ] Measure code accuracy, ROUGE-L
  - [ ] Human evaluation (5-point scale)

- [ ] **Week 8: Documentation**
  - [ ] Write detailed experiment report
  - [ ] Document insights and learnings
  - [ ] Create reusable fine-tuning pipeline

### Phase 3: Advanced Experiments (Months 3-6)

- [ ] RAG pipeline (retrieve code before generating)
- [ ] Multi-task fine-tuning
- [ ] Continuous fine-tuning (auto-train on new commits)
- [ ] Model quantization and deployment

---

## Current Blockers

**None** - All foundation work complete, ready to start physical deployment

---

## Next Immediate Actions

1. **Create GitHub bot accounts** (1-2 hours)
   - Follow `bootstrap/github/create-bot-account.md`
   - Store tokens in 1Password

2. **Bootstrap M4 Mac mini** (30 min)
   - Run `setup-macos.sh`
   - Configure GitHub auth

3. **Bootstrap M2 Pro Mac mini** (30 min)
   - Run `setup-macos.sh`
   - Install ML tools

4. **Test local CI** (1 hour)
   - Clone test repo
   - Run CI scripts
   - Verify all checks pass

5. **Set up VPN** (Optional, 1-2 hours)
   - Configure WireGuard on Aliyun
   - Install clients on Mac minis
   - Test connectivity

---

## Success Metrics Tracking

### GitHub Actions Minutes Saved

| Month | Baseline (Estimated) | Actual | Savings |
|-------|---------------------|--------|---------|
| Feb 2026 | 100 runs × 5 min = 500 min | TBD | TBD |
| Mar 2026 | 500 min | TBD | TBD |

**Target:** <50 minutes/month (90% reduction)

### Cost Tracking

| Item | Monthly Cost | Status |
|------|--------------|--------|
| GitHub Actions (baseline) | ~$100 | Baseline |
| GitHub Actions (with fleet) | ~$10 | Target |
| Anthropic API (agent runtime) | ~$50 | Estimated |
| VPN bandwidth | ~$5 | Estimated |
| **Total (with fleet)** | **~$65** | **35% savings** |

### Agent Productivity

| Metric | Target | Actual |
|--------|--------|--------|
| Tasks completed/week | 20+ | TBD |
| PR merge rate | 80%+ | TBD |
| CI pass rate | 95%+ | TBD |
| Human intervention rate | <20% | TBD |

---

## Timeline Summary

**Week 1 (Feb 7-14):**
- ✅ Phase 1 complete (planning, documentation, scripts)
- 🚧 Phase 2 in progress (GitHub bot accounts)
- 📅 Phase 3-6 pending (physical deployment, CI testing)

**Week 2 (Feb 15-21):**
- Phase 7-8: MCP integration, agent runtimes
- Phase 9: End-to-end testing

**Week 3-4 (Feb 22-Mar 7):**
- Fine-tune agent workflows
- Start LLM learning journey (Phase 1)

**Month 2-3 (Mar-Apr):**
- Agents fully operational
- Continue LLM experiments
- Expand agent roles

**Month 4-6 (May-Jul):**
- Advanced LLM experiments
- Multi-agent collaboration
- ROI analysis and optimization

---

## Lessons Learned (To Be Updated)

**What worked well:**
- TBD

**What to improve:**
- TBD

**Unexpected challenges:**
- TBD

---

## References

- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Detailed implementation guide
- [SUMMARY.md](SUMMARY.md) - Architecture and cost analysis
- [QUICKSTART.md](QUICKSTART.md) - Fast-track 30-minute guide
- [docs/AGENT_TEAMS.md](docs/AGENT_TEAMS.md) - Agent roles and responsibilities
- [docs/LLM_LEARNING_JOURNEY.md](docs/LLM_LEARNING_JOURNEY.md) - LLM training plan
- GitHub Repository: https://github.com/axinova-ai/axinova-agent-fleet
