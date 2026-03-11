# Repository Guidelines

## Repo Role
This repo defines the Axinova builder fleet: bootstrap scripts, launchd units, OpenClaw orchestration config, MCP examples, and operational runbooks. It is the control plane for builder behavior, not a general application repo.

## First Files To Read
- `README.md` for the current architecture
- `scripts/agent-launcher.sh` for builder behavior
- `integrations/mcp/agent-mcp-config.json` for tool wiring
- `openclaw/` for orchestrator assumptions
- `docs/` for operational context and incident history

## Key Workflows
- `./scripts/agent-launcher.sh <builder-name> ~/workspace 120` runs a builder manually.
- `./scripts/fleet-status.sh` shows fleet health.
- `launchd/` plists are the persistent runtime source of truth.
- `integrations/mcp/` holds MCP examples used by builders and founder flows.

## Editing Rules
- Preserve the current generic-builder model unless the task explicitly changes fleet architecture.
- Keep repo detection aligned with task titles containing `axinova-*` repo names.
- Treat runbooks and incident docs as operational records; append and clarify instead of rewriting historical events.
- If you change builder prompts, routing, or MCP assumptions, update the relevant runbook in the same change.

## Validation
- Verify referenced paths, repo names, service names, poll intervals, and model names still exist.
- For MCP-related edits, ensure they still match the current `axinova-tools` schema.

## Codex MCP Note
The current Codex-visible `axinova-tools` schema can read `percent_done` from Vikunja tasks but cannot write it through `vikunja_update_task`. Founder workflows in Codex should therefore use comments for claim/review markers and only rely on `done=true` for final completion unless the MCP server interface is expanded.
