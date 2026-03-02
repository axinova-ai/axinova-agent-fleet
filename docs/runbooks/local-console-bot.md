# Local Console Bot — Runbook

Discord bot gateway for interacting with M2 Pro's Ollama LLM server from Discord.

## Prerequisites

1. **Discord Developer Portal**: Create a new Bot application at https://discord.com/developers/applications
2. **Enable Message Content Intent** (Settings → Bot → Privileged Gateway Intents)
3. **Invite bot to guild** with scopes: `bot`, permissions: Send Messages, Attach Files, Read Message History
4. **Ollama tunnel**: SSH tunnel from M4 (localhost:11434) → M2 Pro (10.10.10.1:11434) must be running

## Environment Variables

File: `~/.config/axinova/discord-local-console.env` (chmod 600)

```
DISCORD_TOKEN=<bot token from Discord Developer Portal>
OLLAMA_BASE_URL=http://localhost:11434
```

## Install / Uninstall

```bash
# Install (npm ci, env stub, launchd plist)
scripts/local-console/install.sh

# Uninstall (stop service, remove plist)
scripts/local-console/uninstall.sh
```

## Manual Start (for testing)

```bash
cd integrations/discord-local-console
npm ci
DISCORD_TOKEN=xxx OLLAMA_BASE_URL=http://localhost:11434 node index.js
```

## Commands

| Command | Description |
|---------|-------------|
| `!ping` | Bot health + config summary |
| `!ping local` | Ollama health check with latency |
| `!models` | List model aliases + Ollama models |
| `!model <alias>` | Set channel default model |
| `!ask <prompt>` | Send prompt to Ollama, reply in Discord |
| `!status` | Fleet health (Ollama, Vikunja, VPN, agents) |

## Model Aliases

Default aliases (can be extended via `~/.config/axinova/local-console-routing.json`):

| Alias | Model |
|-------|-------|
| `local-general` | `qwen2.5:7b-instruct` |
| `local-code` | `qwen2.5-coder:7b` |

### Adding custom aliases

Edit `~/.config/axinova/local-console-routing.json`:

```json
{
  "aliasMap": {
    "kimi": "kimi-k2.5:latest",
    "llama": "llama3.2:latest"
  },
  "channelDefaults": {},
  "userOverrides": {}
}
```

## Guardrails

- **Rate limit**: 5 requests per 60s per user (in-memory, resets on restart)
- **Single-flight**: One concurrent `!ask` per channel
- **Timeout**: 120s per Ollama request
- **Long output**: >2000 chars attached as `response.txt` file

## Troubleshooting

### Bot won't start
- Check token: `grep DISCORD_TOKEN ~/.config/axinova/discord-local-console.env`
- Check logs: `tail -50 ~/logs/local-console-bot-stderr.log`
- Verify node: `node --version` (must be ≥22)

### Bot online but not responding to commands

**Most common cause: missing intents or partials.**

discord.js v14 requires you to explicitly request Gateway Intents in the client constructor AND enable them in the Developer Portal. The bot will connect fine but silently drop events it hasn't opted into.

| Scenario | Required Intent | Required Partial |
|----------|----------------|-----------------|
| Guild channel messages | `GuildMessages` | — |
| DM messages | `DirectMessages` | `Partials.Channel` |
| Reading message text | `MessageContent` (privileged) | — |

**DM-specific gotcha**: Even with `DirectMessages` intent, discord.js v14 requires `Partials.Channel` because DM channels are not cached by default. Without this partial, the library silently drops all DM events — the bot appears online but never fires `messageCreate` for DMs. No error is logged.

**Checklist when bot doesn't respond:**
1. **Developer Portal** → Bot → Privileged Gateway Intents → **Message Content Intent** enabled? (Required to read message text; without it `message.content` is always empty)
2. **Code** has all four intents: `Guilds`, `GuildMessages`, `DirectMessages`, `MessageContent`
3. **Code** has both partials: `Partials.Message`, `Partials.Channel`
4. **Channel permissions**: Bot role has View Channel + Send Messages in the target channel
5. **Guild vs DM**: If testing via DM, steps 2-3 above are critical
6. **Restart after changes**: Intent changes require a fresh gateway connection (restart the bot)

**Debug technique** — add a raw event listener to see what the gateway actually sends:
```js
client.on('raw', (event) => {
  if (event.t === 'MESSAGE_CREATE') {
    console.log('RAW:', event.d.author?.username, event.d.content?.slice(0, 50));
  }
});
```
If this fires but `messageCreate` doesn't, it's a partials issue. If this doesn't fire, it's an intent or permissions issue.

### `!ask` returns error
- Check Ollama tunnel: `curl -s http://localhost:11434/api/tags | jq .`
- Check model exists: `curl -s http://localhost:11434/api/tags | jq '.models[].name'`
- Use `!ping local` to verify connectivity

### Launchd issues
```bash
# Check status
launchctl list | grep local-console

# Restart
launchctl kickstart -k gui/$(id -u)/com.axinova.local-console-bot

# View logs
tail -f ~/logs/local-console-bot-stdout.log
```

## Architecture

```
Discord (user types !ask "hello")
    │ WebSocket (discord.js)
    ▼
index.js (M4 Mac Mini, agent01)
    │ command dispatch by prefix "!"
    ▼
commands/ask.js
    │ 1. Rate limit check
    │ 2. Single-flight check
    │ 3. Resolve model alias
    ▼
lib/ollama.js → POST http://localhost:11434/api/generate
    │ (SSH tunnel → M2 Pro 10.10.10.1:11434)
    ▼
Reply in Discord
```
