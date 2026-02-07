# Axinova Agent Fleet

Multi-agent team infrastructure running on Mac minis for autonomous software development, avoiding GitHub Actions costs while enabling AI research and learning.

## Vision

Transform two Mac minis into **specialized agent teams** (not just single agents) that autonomously handle software development, operations, marketing, customer support, and AI research.

## Team Architecture

### Agent Team 1 (M4 Mac mini) - Production Team
**10-core CPU, 24GB RAM**

Specialized roles:
- 🔧 **Backend Engineer** - Go APIs, database design, tests
- 🎨 **Frontend Engineer** - Vue 3, TypeScript, UI/UX
- 🚀 **DevOps Engineer** - CI/CD, deployments, monitoring
- 📋 **Product Manager** - Roadmap, specs, metrics
- 📢 **Sales & Marketing** - Campaigns, content, ads

### Agent Team 2 (M2 Pro Mac mini) - Research & Learning Team
**10-core CPU, 16-core GPU, 32GB RAM**

Specialized roles:
- 🤖 **AI Researcher** - Train LLMs, fine-tune, evaluate
- 🔬 **Researcher & Data Analyst** - Market research, data analysis
- 💬 **Customer Support** - Issues, docs, FAQs
- 🧪 **QA & Testing** - E2E tests, security, coverage
- 📝 **Technical Writer** - API docs, runbooks, tutorials

## Key Features

✅ **Local CI/CD** - Run tests, builds, security checks on Mac minis before GitHub push
✅ **Multi-Role Agents** - 10 specialized agents (backend, frontend, PM, AI researcher, etc.)
✅ **Cost Savings** - Avoid GitHub Actions minutes ($100+/month → ~$10/month)
✅ **LLM Learning Lab** - Train domain-specific models, fine-tune Llama 3, experiment
✅ **MCP Integration** - Agents control infrastructure (Vikunja, SilverBullet, Portainer, Grafana)
✅ **Secure by Design** - VPN, SSH keys, branch protection, SOPS encryption

## Quick Start

**30-minute fast track:** [QUICKSTART.md](QUICKSTART.md)

### 1. Bootstrap Mac Mini (15 min per mini)

```bash
# SSH to Mac mini
ssh your-user@mac-mini.local

# Run bootstrap (one command)
curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash

# Configure GitHub bot
sudo -i -u axinova-agent
cd ~/workspace/axinova-agent-fleet
./bootstrap/github/setup-bot-token.sh 1  # Use 2 for Agent Team 2
```

### Run Local CI

```bash
cd /Users/weixia/axinova/axinova-agent-fleet
./runners/local-ci/run_ci.sh backend /Users/weixia/axinova/axinova-home-go
./runners/local-ci/run_ci.sh frontend /Users/weixia/axinova/axinova-home-web
```

### Deploy Full Stack

```bash
./runners/orchestration/full-stack-deploy.sh axinova-home dev
```

## Architecture

- **Local CI**: Run tests, builds, security checks on Mac minis before pushing
- **GitHub Actions**: Only triggered on merge to `main` (your approval)
- **GitOps**: Uses existing `axinova-deploy` for deployment orchestration
- **MCP Integration**: Leverages `axinova-mcp-server-go` for Vikunja, SilverBullet, Portainer

### 2. Test Local CI (5 min)

```bash
# Clone test repo
git clone git@github.com:axinova-ai/axinova-home-go.git ~/workspace/axinova-home-go

# Run CI
cd ~/workspace/axinova-agent-fleet
./runners/local-ci/run_ci.sh backend ~/workspace/axinova-home-go

# Expected: ✅ Go CI passed
```

### 3. Deploy Full Stack (10 min)

```bash
./runners/orchestration/full-stack-deploy.sh axinova-home dev
```

## Repository Structure

```
📁 bootstrap/          # Mac mini setup (Homebrew, VPN, GitHub)
📁 runners/            # Local CI (Go, Vue, Docker) + deployment
📁 github/             # Workflow templates, PR automation
📁 integrations/       # MCP server integration
📁 docs/               # Agent teams, LLM journey, runbooks, security
📁 scripts/            # Quick SSH, fleet status utilities

📄 QUICKSTART.md       # 30-minute fast track guide
📄 IMPLEMENTATION.md   # Detailed 8-phase implementation (19KB)
📄 PROGRESS.md         # Progress tracking and timeline
📄 SUMMARY.md          # Architecture, cost analysis (12KB)
```

## Security

- Bot tokens: Fine-grained GitHub PATs, stored in 1Password
- Secrets: SOPS + age encryption
- Network: WireGuard VPN to Singapore, Thunderbolt bridge between minis
- Isolation: Dedicated `axinova-agent` user with restricted permissions

## Documentation

### Getting Started
- **[QUICKSTART.md](QUICKSTART.md)** - 30-minute fast track
- **[IMPLEMENTATION.md](IMPLEMENTATION.md)** - Detailed 8-phase guide
- **[PROGRESS.md](PROGRESS.md)** - Progress tracking and timeline
- **[SUMMARY.md](SUMMARY.md)** - Architecture and cost analysis

### Agent Teams
- **[Agent Teams Structure](docs/AGENT_TEAMS.md)** - 10 specialized roles, coordination, metrics
- **[Agent Roles Runbook](docs/runbooks/agent-roles.md)** - Team responsibilities and permissions

### LLM Learning Journey
- **[LLM Learning Journey](docs/LLM_LEARNING_JOURNEY.md)** - Train from scratch + fine-tune Llama 3
  - Phase 1: Character-level transformer on Axinova docs
  - Phase 2: LoRA fine-tuning for code generation
  - Phase 3: RAG, multi-task, quantization experiments

### Operations
- **[Remote Access](docs/runbooks/remote-access.md)** - SSH, VPN, mosh, Thunderbolt
- **[Rollback Procedures](docs/runbooks/rollback.md)** - Emergency rollback guide
- **[Threat Model](docs/threat-model.md)** - Security analysis and mitigations

## LLM Learning Journey (M2 Pro Mac Mini)

The M2 Pro Mac mini serves as a dedicated **AI research lab**:

**Phase 1 (Weeks 1-4):** Train a tiny character-level transformer from scratch
- Corpus: Axinova documentation, code comments
- Model: 2-layer transformer, ~1M parameters
- Goal: Understand training fundamentals

**Phase 2 (Weeks 5-8):** Fine-tune Llama 3 8B on code generation
- Technique: LoRA (low-rank adaptation)
- Dataset: 100-500 Axinova code examples
- Goal: Compare pre-training vs. fine-tuning

**Phase 3 (Months 3-6):** Advanced experiments
- RAG pipeline for code search
- Multi-task fine-tuning
- Continuous fine-tuning on new commits
- Model quantization and deployment

**Deliverables:**
- Trained models and checkpoints
- Evaluation benchmarks
- Reusable training pipeline
- Wiki documentation with insights

See: [docs/LLM_LEARNING_JOURNEY.md](docs/LLM_LEARNING_JOURNEY.md)

## Success Metrics

**Cost Savings:**
- GitHub Actions: ~$100/month → ~$10/month (90% reduction)
- Platform fees: $0.002/min avoided (starting Mar 1, 2026)
- ROI: Payback in 12 months, net savings ~$600/year

**Productivity:**
- CI feedback: 5 min (local) vs. 10+ min (GitHub)
- Agent task completion: Target >80%
- PR merge rate: Target >80% without changes

**Learning:**
- LLM experiments: 1-2 per month
- Wiki documentation: Updated weekly
- Knowledge shared via tutorials and papers

## Why Agent Fleet?

**Problem:** GitHub Actions costs add up fast
- Free tier: 2,000 minutes/month (burns in ~2 weeks with multiple repos)
- Platform fee: $0.002/min starting March 2026 (even for self-hosted!)
- Our usage: ~100 runs/month × 5 min = 500 min = $100+/month

**Solution:** Run CI locally on Mac minis
- Tests, builds, security checks before GitHub push
- GitHub Actions only run on merge to main (human approval)
- Mac minis already owned (M4 + M2 Pro)

**Bonus:** AI research and multi-agent collaboration
- M2 Pro GPU perfect for LLM fine-tuning experiments
- Multi-role agents (not just CI) handle full software lifecycle
- Learning opportunity: hands-on experience with agent orchestration

## Support

- **Implementation questions:** [IMPLEMENTATION.md](IMPLEMENTATION.md)
- **Quick help:** [QUICKSTART.md](QUICKSTART.md)
- **Issues:** https://github.com/axinova-ai/axinova-agent-fleet/issues
- **Claude Code help:** `/help`
