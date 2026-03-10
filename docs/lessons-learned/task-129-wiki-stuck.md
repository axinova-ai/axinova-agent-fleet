# Lesson Learned: Task #129 — Wiki Task Stuck for 5+ Hours

**Date:** 2026-03-08
**Task:** `[axinova-agent-fleet] Document agent fleet architecture and tech stack in SilverBullet wiki`
**Impact:** Single wiki task took ~5 hours of debugging across 50+ builder attempts before completing in 90 seconds
**Severity:** Critical — exposed 5 cascading failures in the agent fleet infrastructure

---

## Timeline

| Time | Event |
|------|-------|
| 14:48 | Task #129 created via orchestrator |
| 22:48 | First builder claims task — crashes immediately |
| 00:37–02:43 | 8+ builders repeatedly claim, crash, reset — stampede loop |
| 02:39 | BLOCKED comments appear: "WIKI_PAGES: field not found in description" |
| 02:40 | 8 builders simultaneously claim the reset task (race condition) |
| 02:43 | 10 builders simultaneously claim (race condition worsens) |
| 03:02 | Root cause #1 found: description was markdown, Vikunja needs HTML |
| 03:10 | Root cause #2 found: `update_vikunja_task()` wipes description on every update |
| 03:16 | Root cause #3 found: race condition — no claim locking |
| 03:20 | Root cause #4 found: `set -euo pipefail` crashes from unbound vars and `local` outside function |
| 03:25 | Root cause #5 found: GFW blocks TLS to SilverBullet (curl exit 35) |
| 03:55 | All 5 fixes deployed + SSH tunnel created |
| 03:58 | Builder-5 claims task, Codex CLI executes |
| 03:59 | Task completed successfully in 90 seconds |

---

## Root Causes (5 Cascading Failures)

### 1. Vikunja Stores Descriptions as HTML, Not Markdown

**Symptom:** Task description set via curl returned success (875 chars in response), but subsequent GET returned empty string.

**Root Cause:** Vikunja's API accepts and stores descriptions as HTML. When raw markdown is sent, Vikunja silently drops/clears it. The MCP tool hint confirmed: *"Descriptions are stored as HTML — use HTML tags or plain text, not raw markdown."*

**Fix:** Send descriptions with HTML tags (`<h2>`, `<p>`, `<ul><li>`, etc.) instead of markdown.

**Detection:** Could have been caught by reading the MCP tool description, or by immediately re-fetching the task after setting the description to verify persistence.

```bash
# WRONG — markdown gets silently dropped
curl -X POST .../tasks/129 -d '{"description": "## Context\n- item 1"}'

# CORRECT — HTML persists
curl -X POST .../tasks/129 -d '{"description": "<h2>Context</h2><ul><li>item 1</li></ul>"}'
```

---

### 2. Vikunja POST Replaces ALL Fields (Not Partial Update)

**Symptom:** After setting description via one API call, a subsequent `update_vikunja_task` call to change `percent_done` would wipe the description back to empty.

**Root Cause:** Vikunja's `POST /api/v1/tasks/{id}` is a full-replace operation, not a partial update. Any field not included in the payload is reset to its default value (empty string for description, false for done, etc.).

**Fix:** Modified `update_vikunja_task()` to first GET the existing task, then merge the existing `description` and `title` into the update payload before POSTing.

```bash
# WRONG — wipes description
update_vikunja_task "$task_id" '{"percent_done": 0.5}'

# CORRECT — preserve existing fields
existing=$(vikunja_api GET "/tasks/$task_id")
existing_desc=$(echo "$existing" | jq -r '.description // ""')
# Merge into payload before POST
```

**Also affects:** The MCP `vikunja_update_task` tool has the same bug — omitting the optional `description` parameter sends an empty string, wiping the existing description. Always include description when using the MCP tool.

---

### 3. No Claim Locking — Builder Stampede

**Symptom:** At 02:40, 8 builders simultaneously claimed the same task. At 02:43, 10 builders claimed it. All 16 builders racing to claim a single task.

**Root Cause:** `poll_for_task()` returns the first task with `percent_done == 0`. All builders poll on the same interval (120s) and were restarted simultaneously, so they all poll at the same moment, all see the same unclaimed task, and all try to claim it.

`claim_task()` immediately sets `percent_done = 0.5` without checking if another builder already claimed it. No locking, no optimistic concurrency.

**Fix (two-part):**

1. **Random claim delay (0-5s):** Before claiming, each builder waits a random 0-5 seconds. This spreads out the claims so one builder gets there first.

2. **Re-check after delay:** After the delay, re-read the task. If `percent_done != 0`, another builder already claimed it — back off.

3. **Poll jitter (0-15s):** Added random 0-15s jitter to the poll sleep interval so builders don't all poll at the same moment.

```bash
claim_task() {
  local delay=$((RANDOM % 6))
  sleep "$delay"

  # Re-check: did another builder claim it during our delay?
  local current_pct=$(vikunja_api GET "/tasks/$task_id" | jq -r '.percent_done')
  if [[ "$current_pct" != "0" ]]; then
    log "Already claimed — skipping"
    return 1
  fi

  update_vikunja_task "$task_id" '{"percent_done": 0.5}'
}
```

**Result:** Reduced from 10 builders claiming to exactly 1 (sometimes 2 with 0s delay ties).

**Future improvement:** True distributed locking via Vikunja task assignment or a Redis lock. The random delay is a pragmatic 90% solution.

---

### 4. `set -euo pipefail` Crashes on Multiple Code Paths

**Symptom:** Builder processes crash and restart every 60 seconds (launchd ThrottleInterval). No visible error in main log, only in stderr log.

**Root Cause:** Three separate `set -euo pipefail` violations:

#### 4a. `REPO_PATH: unbound variable` in `check_pr_health()`
`check_pr_health()` uses `cd "$REPO_PATH"` but `REPO_PATH` is only set inside `execute_task()` / `execute_wiki_task()`. On loop #3 (PR health check interval) without any task executed, `REPO_PATH` is unbound → `set -u` kills the script.

**Fix:** Guard with `[[ -z "${REPO_PATH:-}" ]]` check at the top of `check_pr_health()`.

#### 4b. `local: can only be used in a function`
Added `local jitter=$((RANDOM % 16))` in the main `while true` loop (not inside a function). Bash's `local` keyword only works inside functions → error under `set -e`.

**Fix:** Use `_jitter` (regular variable) instead of `local jitter`.

#### 4c. `curl` exit code 35 in `silverbullet_get_page()`
The `curl -sf` call to SilverBullet returned exit code 35 (TLS error). The function didn't have `|| true`, so `set -e` killed the script when the curl result was assigned to a variable.

**Fix:** Added `|| true` to `silverbullet_get_page()` and a 30-second timeout (`-m30`).

**Key lesson:** With `set -euo pipefail`, EVERY command that can fail must have `|| true` or be in an `if` statement. Especially:
- Command substitutions: `var=$(cmd_that_might_fail)` — fatal without `|| true`
- `local` keyword — only inside functions
- All variable references — must use `${VAR:-}` for optional variables

---

### 5. GFW Blocks TLS Handshake to SilverBullet

**Symptom:** `curl -sf "https://wiki.axinova-internal.xyz/..."` returns exit code 35 (`Recv failure: Connection reset by peer`) during TLS handshake.

**Root Cause:** The Mac Minis are in China. SilverBullet runs on `ax-sas-tools` (121.40.188.25, Aliyun China) behind Traefik with TLS. The GFW appears to be blocking or resetting certain TLS connections, possibly due to SNI inspection of the `.xyz` domain.

**Fix:** Created SSH tunnel on both Mac Minis:
- Port 3001 (local) → ax-sas-tools:3000 (SilverBullet HTTP, bypassing Traefik/TLS)
- Deployed as launchd plist: `com.axinova.silverbullet-tunnel.plist`
- Updated `SILVERBULLET_URL` from `https://wiki.axinova-internal.xyz` to `http://localhost:3001`

```xml
<!-- SSH tunnel plist -->
<string>ssh</string>
<string>-N</string>
<string>-L</string>
<string>3001:127.0.0.1:3000</string>
<string>root@121.40.188.25</string>
```

**Also needed:** SilverBullet auth token (`admin:123321`) deployed to `~/.config/axinova/secrets.env` on both machines — it was missing entirely.

---

## Additional Issues Found and Fixed

### Comment JSON Escaping
`add_task_comment()` interpolated the comment text directly into a JSON string without escaping. Special characters (quotes, newlines, backslashes) would produce malformed JSON, causing silent failures.

**Fix:** Pipe comment through `jq -Rs .` for proper JSON string escaping.

### Missing Info in Task Comments
- STARTED comment said `Model: codex→kimi` (hardcoded, inaccurate)
- COMPLETED comment didn't include: model name, wiki page names, wiki URLs, agent ID

**Fix:** Updated both comments with accurate runtime information.

### `grep -oP` Not Available on macOS
The WIKI_PAGES extraction used `grep -oP` (Perl regex) which only works on Linux. Both Mac Minis run macOS where `-P` is not available.

**Fix:** Replaced with portable `sed -n '/PATTERN/{ s/...//; p; }'` pattern.

---

## Debugging Checklist for Stuck Tasks

When a task is stuck (claimed but not completing), check these in order:

1. **Check stderr logs** — `~/logs/agent-builder-N-stderr.log`
   - `unbound variable` → missing `${VAR:-}` guard
   - `local: can only be used in a function` → `local` in main scope
   - `exit code` from curl/git → network or auth issue

2. **Check task state** — `curl .../tasks/ID | jq '.percent_done, .description | length'`
   - `percent_done=0.5` + no builder working = stuck claim, needs reset
   - `description` empty = wiped by partial update

3. **Check network** — from the Mac Mini, not your local machine
   - SilverBullet: `curl -sfm5 http://localhost:3001/.fs/test.md`
   - Vikunja: `curl -sfm5 http://localhost:3456/api/v1/projects`
   - GitHub: `gh auth status`

4. **Check launchd** — `launchctl list | grep axinova`
   - PID `-` = not running (crashed)
   - Exit code `1` = script error (check stderr)
   - Exit code `-15` = SIGTERM (killed by restart)

5. **Check race condition** — `grep "Claim" ~/logs/agent-builder-*.log | grep "TASK_ID" | wc -l`
   - More than 1 = race condition (check if claim locking is working)

---

## Prevention Measures

| Issue | Prevention |
|-------|-----------|
| HTML vs markdown | Always test description persistence: set, then immediately GET to verify |
| Field wiping | `update_vikunja_task()` now preserves existing fields automatically |
| Race condition | Claim delay + re-check + poll jitter deployed |
| `set -e` crashes | Run `bash -n script.sh` for syntax check; test all code paths with empty/missing variables |
| Network issues | SSH tunnels for all internal services; `|| true` on all curl calls |
| Missing secrets | Startup log now shows `Models available: codex=X kimi=X ollama=X`; add SilverBullet token check |

---

## Key Takeaways

1. **Vikunja API is full-replace, not partial-update.** Every POST must include ALL fields you want to keep. This is the single most dangerous gotcha.

2. **`set -euo pipefail` is a double-edged sword.** It catches bugs early but makes every unhandled error fatal. In a long-running agent script, every curl, git, and command substitution must be guarded.

3. **16 builders polling the same queue need locking.** Random delay is a pragmatic 90% solution. True locking (via Vikunja task assignment or external lock) would be better for production.

4. **Always test from the builder's environment**, not your local machine. The builders are in China behind the GFW — network paths are different.

5. **Check stderr, not just stdout.** The main log (`agent-builder-N.log`) showed no errors. The crash was only visible in `agent-builder-N-stderr.log`.

6. **Cascading failures are the norm.** This task had 5 independent bugs that all had to be fixed before it could work. Any one of them would have blocked execution. Debug systematically — fix one layer, test, find the next.
