# Axinova Agent Fleet

Local CI/CD agent infrastructure running on Mac minis to avoid GitHub Actions minutes consumption.

## Overview

Two-agent team model:
- **Agent1 (M4 Mac mini)**: Delivery-focused (PRs, features, refactoring)
- **Agent2 (M2 Pro Mac mini)**: Learning + stability (AI experiments, docs, tests)

## Quick Start

### Bootstrap a Mac mini

```bash
# From your laptop, SSH to the Mac mini
ssh your-user@mac-mini.local

# Run bootstrap script
curl -fsSL https://raw.githubusercontent.com/axinova-ai/axinova-agent-fleet/main/bootstrap/mac/setup-macos.sh | bash
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

## Repository Structure

```
bootstrap/          # Mac mini setup scripts
runners/            # CI and orchestration scripts
github/             # Workflow templates, PR automation
integrations/       # MCP, Vikunja, SilverBullet integrations
docs/               # Runbooks, architecture, security
scripts/            # Quick access utilities
```

## Security

- Bot tokens: Fine-grained GitHub PATs, stored in 1Password
- Secrets: SOPS + age encryption
- Network: WireGuard VPN to Singapore, Thunderbolt bridge between minis
- Isolation: Dedicated `axinova-agent` user with restricted permissions

## Documentation

- [Threat Model](docs/threat-model.md)
- [Remote Access](docs/runbooks/remote-access.md)
- [Agent Roles](docs/runbooks/agent-roles.md)
- [Rollback Procedures](docs/runbooks/rollback.md)

## Support

Questions or issues? Check `/help` or open an issue.
