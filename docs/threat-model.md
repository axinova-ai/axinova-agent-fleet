# Agent Fleet Threat Model

## Attack Surface

### 1. GitHub Bot Tokens

**Risk:** Tokens grant write access to repositories
- Attacker with token can push malicious code, create PRs, modify issues

**Mitigations:**
- Fine-grained PATs with minimal repository access
- Limited permissions (contents:write, PR:write, issues:write only)
- 1-year expiration with calendar reminders
- Stored in 1Password, never committed to git
- Separate tokens for Agent1 and Agent2 (blast radius containment)

**Monitoring:**
- GitHub audit log review (monthly)
- Alert on unexpected repo access or push to main
- Rate limiting on API calls

### 2. MCP Server Credentials

**Risk:** Credentials allow infrastructure control (Portainer, Vikunja, etc.)

**Mitigations:**
- SOPS + age encryption for secrets
- Read-only tokens where possible (Prometheus, Grafana)
- TLS verification enabled in production
- Secrets stored outside git repo
- Rotation policy (quarterly)

**Monitoring:**
- MCP server access logs
- Prometheus alerts on unexpected API calls
- SilverBullet audit trail for wiki changes

### 3. SSH Access to Mac Minis

**Risk:** Compromised SSH grants full system access

**Mitigations:**
- Key-based authentication only (password auth disabled)
- Separate `axinova-agent` user with restricted permissions
- No direct sudo for dangerous commands
- Firewall rules (only VPN + Thunderbolt network access)
- SSH key passphrase required

**Monitoring:**
- SSH login logs (`/var/log/system.log`)
- Failed authentication alerts
- Unusual process spawns (via `auditd` or similar)

### 4. WireGuard VPN

**Risk:** VPN compromise allows access to internal services

**Mitigations:**
- Strong WireGuard keys (256-bit)
- Firewall on Aliyun SG server (only port 51820/udp)
- AllowedIPs restricted to VPN subnet (10.100.0.0/24)
- PersistentKeepalive to detect dead connections
- Separate VPN keys per device

**Monitoring:**
- WireGuard connection logs
- Unusual traffic patterns (IDS on Aliyun)
- Periodic key rotation (annually)

### 5. Agent Runtime Security

**Risk:** Malicious code execution via agent

**Mitigations:**
- Local CI runs before GitHub push (catch issues early)
- Code review on all PRs (even from agents)
- Agents push to `agent/*` branches, not `main` (human approval required)
- Sandboxed execution (Docker for builds, separate user for agent)
- Static analysis in CI (govulncheck, npm audit)

**Monitoring:**
- Review agent-created PRs before merge
- SilverBullet wiki logs all agent actions
- Vikunja tasks track agent work

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│ Your Laptop (Trusted)                                       │
│  - Full admin access                                        │
│  - Manual code review and merge approval                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ SSH + VPN
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ Mac Minis (Semi-Trusted)                                    │
│  - Agent runtime with restricted permissions                │
│  - Can push code to agent/* branches (not main)             │
│  - Can create PRs (requires your approval)                  │
│  - Can deploy to dev (limited blast radius)                 │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ GitHub API + MCP
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ External Services (Untrusted)                               │
│  - GitHub (public, but authenticated)                       │
│  - Aliyun Singapore (production infrastructure)             │
│  - MCP-connected services (Vikunja, SilverBullet, etc.)     │
└─────────────────────────────────────────────────────────────┘
```

## Attack Scenarios

### Scenario 1: Stolen GitHub Bot Token

**Attack:** Attacker obtains Agent1 bot token from leaked env var

**Impact:**
- Can push to allowed repos (home-go, home-web, miniapp-builder-go/web, deploy)
- Can create malicious PRs
- Cannot merge to main (branch protection prevents bot from approving own PR)

**Response:**
1. Revoke token immediately on GitHub
2. Generate new token with updated scopes
3. Review recent commits from bot account (last 7 days)
4. Audit git history for suspicious changes
5. Rotate all secrets in SOPS-encrypted files

**Prevention:**
- Never log GITHUB_TOKEN in agent output
- Use 1Password CLI to retrieve token at runtime (not env file)
- Set short expiration (1 year max)

### Scenario 2: Compromised Mac Mini

**Attack:** Attacker gains SSH access via stolen key

**Impact:**
- Can run code as `axinova-agent` user
- Can push to GitHub repos
- Can access VPN and internal services

**Response:**
1. Disconnect Mac mini from network immediately
2. Revoke SSH key from `~/.ssh/authorized_keys` on all systems
3. Revoke GitHub bot token
4. Review git history and infrastructure changes
5. Re-image Mac mini from clean backup
6. Rotate all secrets

**Prevention:**
- SSH key with strong passphrase
- Firewall rules to limit SSH access to VPN only
- Monitor `/var/log/system.log` for unusual logins

### Scenario 3: Malicious Code Injection via Agent

**Attack:** Agent generates vulnerable code, pushes to repo

**Impact:**
- Vulnerability in production if merged without review
- Potential RCE, SQLi, XSS, etc.

**Response:**
1. Identify vulnerable code in PR review
2. Reject PR, add test case to catch similar issues
3. Review agent's training data/prompts for root cause
4. Update local CI checks to catch this vulnerability class

**Prevention:**
- Mandatory code review on all PRs (even from agents)
- govulncheck, npm audit in CI
- Static analysis tools (golangci-lint)
- Never auto-merge agent PRs

## Security Hardening Checklist

### Mac Mini Setup
- [ ] Firewall enabled (only VPN + Thunderbolt + SSH)
- [ ] Password authentication disabled for SSH
- [ ] `axinova-agent` user created with minimal sudo
- [ ] Full disk encryption enabled
- [ ] Automatic updates enabled for macOS
- [ ] Screen sharing password-protected

### GitHub Configuration
- [ ] Fine-grained PATs created with minimal scopes
- [ ] Tokens stored in 1Password
- [ ] Branch protection on `main` (require PR + review)
- [ ] No bot accounts have admin permissions
- [ ] Two-factor authentication enabled for all accounts

### Network Security
- [ ] WireGuard VPN with strong keys
- [ ] Firewall on Aliyun SG server (port 51820 only)
- [ ] AllowedIPs restricted to VPN subnet
- [ ] Thunderbolt bridge uses private IP range (169.254.0.0/16)

### Secrets Management
- [ ] All secrets SOPS-encrypted with age
- [ ] Age keys stored outside git repo
- [ ] Secrets never committed to version control
- [ ] 1Password CLI installed and configured
- [ ] Quarterly secret rotation calendar

### Monitoring & Auditing
- [ ] GitHub audit log reviewed monthly
- [ ] SSH login logs monitored weekly
- [ ] MCP server access logs retained (90 days)
- [ ] Agent actions logged to SilverBullet wiki
- [ ] Prometheus alerts configured for anomalies

## Compliance Considerations

Since this is a personal/small team setup (not enterprise), formal compliance is not required. However, best practices include:

- **Data Residency:** All code and secrets on Singapore/US servers (no China/Russia)
- **Access Logging:** Retain logs for 90 days minimum
- **Incident Response:** Document all security incidents in wiki
- **Backup:** Weekly backups of Mac mini configurations

## References

- [GitHub Fine-Grained PAT Documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [WireGuard Security Best Practices](https://www.wireguard.com/quickstart/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [SOPS Documentation](https://github.com/getsops/sops)
