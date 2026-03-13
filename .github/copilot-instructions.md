# Axinova Agent Fleet - Copilot Instructions

This workspace uses Axinova MCP tools and workspace skills for fleet and Vikunja operations.

## Use MCP First For External Systems

- Prefer the `axinova-tools` MCP server for Vikunja, Portainer, Grafana, Prometheus, SilverBullet, and Registry UI actions.
- For Vikunja task and project workflows, use MCP tools instead of browser-based exploration whenever possible.

## Prefer Workspace Skills For Fleet Workflows

When the user asks for these workflows, prefer the matching skill from `.github/skills/`:

- `task-status` or `ax-task-status` for fleet overview in Vikunja project 13
- `pickup-task` or `ax-pickup-task` for founder claim/takeover flows
- `complete-task` or `ax-complete-task` for PR and completion flows
- `reroute-task` or `ax-reroute-task` for sending tasks back to builders
- `ax-create-agent-project` for new agent-managed Vikunja projects
- `ax-test-mcp-project` after Vikunja MCP changes
- `ax-test-scheduler` after scheduler changes

## Repo-Specific Notes

- This repo is the control plane for the builder fleet. Preserve the generic-builder model unless the user explicitly asks to change fleet architecture.
- Task titles and descriptions should keep repo detection explicit by mentioning `axinova-*` repo names.
- For MCP-related changes, keep workspace skills and operational docs aligned.