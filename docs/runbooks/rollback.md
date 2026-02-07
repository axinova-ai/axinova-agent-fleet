# Rollback Runbook

Emergency procedures for rolling back deployments.

## Quick Rollback (Docker Compose)

If a recent deployment caused issues, roll back to previous image:

```bash
# SSH to Aliyun server
ssh root@<aliyun-sg-ip>

# Find previous image tag
docker images ghcr.io/axinova-ai/axinova-home-go --format "{{.Tag}}" | head -5

# Edit values.yaml to use previous tag
cd /opt/axinova-deploy/envs/prod/apps/axinova-home-go
vim values.yaml  # Change image.tag to previous SHA

# Redeploy with previous image
cd /opt/axinova-deploy
./scripts/compose/deploy-service.sh prod axinova-home-go

# Wait for health check
./scripts/compose/wait-healthy.sh prod axinova-home-go
```

## Git Revert (Code Rollback)

If the issue is in code (not deployment):

```bash
# On your laptop
cd ~/axinova/axinova-home-go

# Find the problematic commit
git log --oneline -10

# Revert the commit (creates new commit)
git revert <commit-sha>

# Push to trigger CI/CD
git push origin main
```

**Never use:**
- `git reset --hard` on main branch (destroys history)
- `git push --force` to main (corrupts shared history)

## Database Migration Rollback

If a migration caused issues:

```bash
# SSH to server
ssh root@<aliyun-sg-ip>

# Check migration history
docker exec -it axinova-home-go-db-1 psql -U postgres -d axinova_home -c "SELECT * FROM schema_migrations;"

# Roll back one migration
cd /opt/axinova-home-go
make migrate-down

# Or specify version
migrate -path migrations -database "$DB_URL" down 1
```

**Recovery steps:**
1. Backup database first: `pg_dump -U postgres axinova_home > backup.sql`
2. Roll back migration
3. Verify application starts
4. Restore data if needed: `psql -U postgres axinova_home < backup.sql`

## Rollback Checklist

### Before Rollback

- [ ] Identify root cause (logs, metrics, error reports)
- [ ] Document issue in SilverBullet wiki
- [ ] Notify team (if applicable)
- [ ] Backup current state (database, configs)

### During Rollback

- [ ] Stop current deployment
- [ ] Deploy previous known-good version
- [ ] Verify health checks pass
- [ ] Test critical user flows
- [ ] Monitor logs for new errors

### After Rollback

- [ ] Update Vikunja task with rollback details
- [ ] Post-mortem in wiki (what went wrong, how to prevent)
- [ ] Create GitHub issue to fix root cause
- [ ] Plan re-deployment timeline

## Common Scenarios

### Scenario 1: API Returns 500 Errors

**Symptoms:**
- Health check fails
- Logs show panic or database errors

**Rollback:**
```bash
# Quick: Restart service with previous image
cd /opt/axinova-deploy
vim envs/prod/apps/axinova-home-go/values.yaml  # Revert image.tag
./scripts/compose/deploy-service.sh prod axinova-home-go

# Verify
curl https://axinova.ai/api/health
```

### Scenario 2: Database Migration Failed

**Symptoms:**
- Application won't start
- Logs show migration error

**Rollback:**
```bash
# Roll back migration
cd /opt/axinova-home-go
migrate -path migrations -database "$DB_URL" down 1

# Restart application
docker restart axinova-home-go-api-1
```

### Scenario 3: Frontend Build Broken

**Symptoms:**
- Blank page or JS errors in browser console
- 404 on static assets

**Rollback:**
```bash
# Deploy previous frontend image
cd /opt/axinova-deploy
vim envs/prod/apps/axinova-home-web/values.yaml
./scripts/compose/deploy-service.sh prod axinova-home-web

# Clear CDN cache if using one
# (Axinova doesn't use CDN currently)
```

### Scenario 4: Configuration Error

**Symptoms:**
- Service won't start
- Logs show config validation error

**Rollback:**
```bash
# Revert config change
cd /opt/axinova-deploy
git log envs/prod/apps/axinova-home-go/values.yaml
git revert <commit-sha>
git push

# Redeploy
./scripts/compose/deploy-service.sh prod axinova-home-go
```

## Rollback Automation

**Future improvement:** Create automated rollback script:

```bash
# Example: axinova-agent-fleet/runners/orchestration/rollback.sh
./rollback.sh axinova-home prod  # Rolls back to previous image
```

**Script logic:**
1. Fetch deployment history from git
2. Identify previous image tag (SHA-1)
3. Update values.yaml
4. Deploy
5. Wait for health check
6. If health check fails, roll back further

## Prevention

**To avoid needing rollbacks:**

1. **Staging environment:** Test in stage before prod
2. **Canary deployments:** Roll out to 10% of traffic first
3. **Feature flags:** Disable new features without redeploying
4. **Comprehensive tests:** Catch bugs in CI before merge
5. **Database migrations:** Always reversible (`up` and `down`)

## Contact

For emergency rollback assistance:
- Escalate to human immediately if unsure
- Document all steps in wiki for future reference
- Never guess - verify before executing destructive commands
