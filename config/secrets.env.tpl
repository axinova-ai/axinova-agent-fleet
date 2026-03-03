# ~/.config/axinova/secrets.env.tpl
#
# 1Password secret references — SAFE TO COMMIT (contains no secrets).
# Copy this file to ~/.config/axinova/secrets.env.tpl on each machine,
# then run: op inject -i secrets.env.tpl -o secrets.env
#
# All values use the format: op://VaultName/ItemName/FieldName
# Set up the "Axinova" vault in 1Password with matching item names.

# --- Vikunja ---
VIKUNJA_URL=https://vikunja.axinova-internal.xyz
VIKUNJA_TOKEN=op://Axinova/Vikunja Token/password

# --- Moonshot / Kimi ---
MOONSHOT_API_KEY=op://Axinova/Moonshot Kimi API/credential

# --- Discord ---
DISCORD_WEBHOOK_BACKEND_SDE=op://Axinova/Discord Webhook - backend-sde/url
DISCORD_WEBHOOK_FRONTEND_SDE=op://Axinova/Discord Webhook - frontend-sde/url
DISCORD_WEBHOOK_DEVOPS=op://Axinova/Discord Webhook - devops/url
DISCORD_WEBHOOK_QA=op://Axinova/Discord Webhook - qa/url
DISCORD_WEBHOOK_TECH_WRITER=op://Axinova/Discord Webhook - tech-writer/url
DISCORD_WEBHOOK_ALERTS=op://Axinova/Discord Webhook - alerts/url

# --- SilverBullet Wiki ---
APP_SILVERBULLET__URL=https://wiki.axinova-internal.xyz
APP_SILVERBULLET__TOKEN=op://Axinova/SilverBullet Token/password

# --- GitHub ---
GITHUB_PAT=op://Axinova/GitHub PAT/credential

# --- Portainer ---
PORTAINER_URL=https://portainer.axinova-internal.xyz
PORTAINER_TOKEN=op://Axinova/Portainer Token/password

# --- Grafana ---
GRAFANA_URL=https://grafana.axinova-internal.xyz
GRAFANA_TOKEN=op://Axinova/Grafana Token/password

# --- Ollama (M2 Pro) ---
OLLAMA_HOST=http://localhost:11434
