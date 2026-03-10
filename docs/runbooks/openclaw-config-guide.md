# OpenClaw Configuration Guide

Lessons learned from configuring OpenClaw v2026.3.2 on M4 Mac Mini.

## Key Discovery: Workspace Files Override Agent IDENTITY.md

OpenClaw assembles the system prompt from **workspace files** in `~/.openclaw/workspace/`, NOT from `~/.openclaw/agents/main/agent/IDENTITY.md` alone.

### System Prompt Assembly Order

The gateway injects these files into every session's system prompt:

| File | Purpose | Priority |
|------|---------|----------|
| `~/.openclaw/workspace/SOUL.md` | Core personality, role, communication style | High — shapes all responses |
| `~/.openclaw/workspace/AGENTS.md` | Fleet structure, team info, task routing | High — defines what the bot "knows" about the fleet |
| `~/.openclaw/workspace/IDENTITY.md` | Name, vibe, avatar | Medium |
| `~/.openclaw/workspace/USER.md` | Info about the user (Wei) | Medium |
| `~/.openclaw/workspace/TOOLS.md` | Environment-specific notes (SSH hosts, devices) | Low |
| `~/.openclaw/workspace/MEMORY.md` | Persistent memory across sessions | Medium |
| `~/.openclaw/workspace/HEARTBEAT.md` | Heartbeat config | Low |
| `~/.openclaw/agents/main/agent/IDENTITY.md` | Agent-level identity (also injected) | Medium |

**Lesson:** If you only update `agents/main/agent/IDENTITY.md` but leave stale `workspace/AGENTS.md` and `workspace/SOUL.md`, the bot will use the old fleet info from workspace files.

### How to Update the Bot's Knowledge

1. Update ALL relevant workspace files:
   ```bash
   scp updated-AGENTS.md agent01-vpn:~/.openclaw/workspace/AGENTS.md
   scp updated-SOUL.md agent01-vpn:~/.openclaw/workspace/SOUL.md
   scp updated-MEMORY.md agent01-vpn:~/.openclaw/workspace/MEMORY.md
   scp updated-IDENTITY.md agent01-vpn:~/.openclaw/workspace/IDENTITY.md
   ```

2. Clear old sessions (they cache the old system prompt):
   ```bash
   ssh agent01-vpn 'rm -f ~/.openclaw/agents/main/sessions/*.jsonl && echo "{}" > ~/.openclaw/agents/main/sessions/sessions.json'
   ```

3. Restart OpenClaw:
   ```bash
   ssh agent01-vpn 'launchctl kickstart -k gui/$(id -u)/com.axinova.openclaw'
   ```

**All three steps are required.** Missing any one will result in the bot using stale context.

## Config Format Migration (v2026.2.x → v2026.3.x)

OpenClaw v2026.3.2 completely changed the config format. The old JSON-based config with `providers`, `agents`, `channels` top-level keys is **no longer supported**.

### Old Format (pre-v2026.3.0) — DO NOT USE
```json
{
  "providers": { "moonshot": { ... } },
  "agents": { "task-router": { "model": "...", "bindings": [...] } },
  "gateway": { "channels": { "discord": { ... } } }
}
```

### New Format (v2026.3.2+) — CLI-Configured
```bash
# Auth
openclaw models auth paste-token    # Paste Moonshot API key

# Model
openclaw models set moonshot/kimi-k2.5

# Gateway
openclaw config set gateway.mode local

# Discord
openclaw config set channels.discord.groupPolicy open
```

The config file (`~/.openclaw/openclaw.json`) is auto-managed. Edit via `openclaw config set`, not manually.

### Common Errors After Upgrade

| Error | Fix |
|-------|-----|
| `Unrecognized keys: channels, pairing, providers` | Old config format. Run `openclaw doctor --fix` then reconfigure via CLI |
| `Gateway start blocked: set gateway.mode=local` | `openclaw config set gateway.mode local` |
| `Config validation failed: agents.defaults: Unrecognized key` | Don't manually add keys — use CLI commands |

## Discord Channel Access

### groupPolicy Setting

| Value | Behavior |
|-------|----------|
| `open` | Bot responds in ALL channels it's added to |
| `allowlist` | Bot only responds in explicitly listed guilds/channels |

**Lesson:** `openclaw doctor --fix` may set `groupPolicy: "allowlist"` with an empty allowlist, silently blocking all channel messages. DMs may still work but channels won't respond.

Fix:
```bash
openclaw config set channels.discord.groupPolicy open
```

## Session Memory Persistence

OpenClaw caches conversation context in session files (`~/.openclaw/agents/main/sessions/*.jsonl`). Even after updating workspace files, existing sessions will use the **cached** system prompt until cleared.

**Lesson:** Always clear sessions after updating workspace files. The bot creates new sessions with fresh system prompts on next message.

## Vikunja Integration (No MCP)

OpenClaw v2026.3.2 doesn't support MCP server configuration in its config schema. Instead, the agent uses its native `exec` (bash) tool to run `curl` commands against the Vikunja API.

- Vikunja API: `http://localhost:3456` (via SSH tunnel from M4)
- Token: `~/.config/axinova/vikunja.env` (sourced in bash)
- The IDENTITY.md/AGENTS.md must include curl examples so the model knows how to call the API

## Files Reference

### Repo (source of truth for content)
```
openclaw/task-router-prompt.md    # Full orchestrator prompt (deploy to workspace IDENTITY.md)
openclaw/openclaw.json            # Setup reference (not live config)
```

### Deployed on M4 (live)
```
~/.openclaw/openclaw.json                          # Auto-managed by CLI
~/.openclaw/workspace/IDENTITY.md                  # Full orchestrator prompt
~/.openclaw/workspace/AGENTS.md                    # Fleet structure
~/.openclaw/workspace/SOUL.md                      # Personality and role
~/.openclaw/workspace/MEMORY.md                    # Persistent knowledge
~/.openclaw/workspace/USER.md                      # User info
~/.openclaw/agents/main/agent/IDENTITY.md          # Agent-level identity
~/.openclaw/agents/main/agent/auth-profiles.json   # API keys (Moonshot)
~/.openclaw/agents/main/agent/models.json          # Model config
```

## Deployment Checklist

When making changes to the orchestrator:

- [ ] Update workspace files (AGENTS.md, SOUL.md, MEMORY.md, IDENTITY.md)
- [ ] Clear sessions (`rm *.jsonl`, reset `sessions.json`)
- [ ] Restart OpenClaw (`launchctl kickstart -k`)
- [ ] Verify Discord login in stdout log
- [ ] Test with a DM message
- [ ] Test with a channel message
- [ ] Verify Vikunja API works (`curl localhost:3456`)
